"""
Azure Function for Contract Analysis using Azure Content Understanding.
Stores results in Azure SQL Database.
Triggered via HTTP POST by Logic Apps.
"""

import azure.functions as func
import logging
import json
import time
import os
import struct
import requests
import pyodbc
from azure.identity import DefaultAzureCredential

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)


@app.route(route="analyze-and-store", methods=["POST"])
def analyze_and_store(req: func.HttpRequest) -> func.HttpResponse:
    """
    HTTP trigger function to analyze a contract and store results in Azure SQL.

    Expects either:
    - Binary PDF content in request body with Content-Type: application/pdf
    - JSON body with base64-encoded PDF: {"filename": "contract.pdf", "content": "base64..."}

    Returns: JSON with extracted contract data and database IDs
    """
    logging.info("Contract analysis and storage function triggered")

    try:
        # Get Content Understanding configuration
        base_endpoint = os.environ["CONTENT_UNDERSTANDING_ENDPOINT"]
        api_version = os.environ.get("CONTENT_UNDERSTANDING_API_VERSION", "2025-11-01")
        analyzer_id = os.environ["CONTENT_UNDERSTANDING_ANALYZER_ID"]

        # Azure SQL configuration
        sql_server = os.environ["SQL_SERVER"]
        sql_database = os.environ["SQL_DATABASE"]

        endpoint = f"{base_endpoint}/contentunderstanding/analyzers/{analyzer_id}:analyzeBinary?api-version={api_version}"

        # Get authentication tokens
        credential = DefaultAzureCredential()
        cu_token = credential.get_token("https://cognitiveservices.azure.com/.default")
        sql_token = credential.get_token("https://database.windows.net/.default")

        # Parse request content
        file_content, filename = parse_request(req)

        if not file_content:
            return func.HttpResponse(
                json.dumps({"error": "No file content provided"}),
                status_code=400,
                mimetype="application/json",
            )

        logging.info(f"Processing file: {filename}, size: {len(file_content)} bytes")

        # Analyze the contract
        result = analyze_contract_document(
            file_content=file_content,
            filename=filename,
            endpoint=endpoint,
            token=cu_token.token,
        )

        if "error" in result:
            return func.HttpResponse(
                json.dumps(result), status_code=500, mimetype="application/json"
            )

        # Store in Azure SQL
        db_result = store_in_database(
            result=result,
            server=sql_server,
            database=sql_database,
            token=sql_token.token,
        )

        result["database"] = db_result

        logging.info(
            f"Successfully stored contract {db_result['contract_id']} with "
            f"{len(db_result['party_ids'])} parties and {len(db_result['clause_ids'])} clauses"
        )

        return func.HttpResponse(
            json.dumps(result, default=str),
            status_code=200,
            mimetype="application/json",
        )

    except KeyError as e:
        logging.error(f"Missing environment variable: {e}")
        return func.HttpResponse(
            json.dumps({"error": f"Missing configuration: {e}"}),
            status_code=500,
            mimetype="application/json",
        )
    except Exception as e:
        logging.error(f"Error processing contract: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}), status_code=500, mimetype="application/json"
        )


def parse_request(req: func.HttpRequest) -> tuple[bytes, str]:
    """Parse the incoming request and extract file content and filename."""
    import base64

    content_type = req.headers.get("Content-Type", "")
    logging.info(f"Request Content-Type: {content_type}")

    if "application/pdf" in content_type:
        body = req.get_body()
        logging.info(f"Received raw PDF, first 20 bytes: {body[:20]}")
        # Validate PDF magic bytes
        if body[:4] != b"%PDF":
            logging.warning(
                f"Body does not start with PDF magic bytes! Starts with: {body[:20]}"
            )
        return body, req.headers.get("X-Filename", "uploaded_contract.pdf")

    # Try JSON format
    try:
        body = req.get_json()
        # Handle both 'filename' and 'fileName' (Logic Apps uses capital N)
        filename = body.get("filename") or body.get("fileName", "uploaded_contract.pdf")
        content_base64 = body.get("content", "")
        logging.info(
            f"Received JSON with base64 content, length: {len(content_base64)}"
        )
        decoded = base64.b64decode(content_base64)
        logging.info(f"Decoded PDF, first 20 bytes: {decoded[:20]}")
        # Validate PDF magic bytes
        if decoded[:4] != b"%PDF":
            logging.warning(f"Decoded content does not start with PDF magic bytes!")
        return decoded, filename
    except Exception as e:
        logging.warning(f"JSON parse failed: {e}, falling back to raw body")
        body = req.get_body()
        logging.info(f"Fallback raw body, first 20 bytes: {body[:20]}")
        return body, req.headers.get("X-Filename", "uploaded_contract.pdf")


def analyze_contract_document(
    file_content: bytes, filename: str, endpoint: str, token: str
) -> dict:
    """Analyze a contract document using Azure Content Understanding."""
    logging.info(f"Analyzing: {filename}")
    logging.info(f"Endpoint: {endpoint}")

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/pdf",
    }

    try:
        logging.info("Submitting document to Content Understanding...")
        response = requests.post(
            endpoint, headers=headers, data=file_content, timeout=60
        )
        logging.info(f"Submit response status: {response.status_code}")
    except requests.exceptions.RequestException as e:
        logging.error(f"Request failed: {str(e)}")
        return {"filename": filename, "error": f"Request failed: {str(e)}"}

    if response.status_code != 202:
        logging.error(f"API error: {response.status_code} - {response.text}")
        return {
            "filename": filename,
            "error": f"API returned {response.status_code}: {response.text}",
        }

    operation_location = response.headers.get("Operation-Location")
    if not operation_location:
        logging.error("No Operation-Location header in response")
        return {"filename": filename, "error": "No Operation-Location header"}

    logging.info(f"Operation-Location: {operation_location}")

    # Poll for results
    poll_headers = {"Authorization": f"Bearer {token}"}

    for attempt in range(60):
        time.sleep(2)
        try:
            result_response = requests.get(
                operation_location, headers=poll_headers, timeout=30
            )
        except requests.exceptions.RequestException as e:
            logging.warning(f"Poll attempt {attempt + 1} failed: {str(e)}")
            continue

        if result_response.status_code == 200:
            result_data = result_response.json()
            status = result_data.get("status")
            logging.info(f"Poll attempt {attempt + 1}: status = {status}")

            if status == "Succeeded":
                logging.info("Analysis succeeded, extracting fields...")
                contents = result_data.get("result", {}).get("contents", [])
                if contents:
                    fields = contents[0].get("fields", {})
                    extracted = {
                        "filename": filename,
                        "title": extract_field_value(fields.get("Title")),
                        "parties": extract_parties(fields),
                        "dates": extract_dates(fields),
                        "duration": extract_field_value(fields.get("ContractDuration")),
                        "jurisdictions": extract_array_field(
                            fields.get("Jurisdictions")
                        ),
                        "clauses": extract_clauses(fields),
                        "raw_fields": fields,
                        "markdown": contents[0].get("markdown", ""),
                    }
                    logging.info(
                        f"Extracted: {len(extracted.get('parties', []))} parties, {len(extracted.get('clauses', []))} clauses"
                    )
                    return extracted
                logging.warning("No contents in result")
                return {"filename": filename, "raw_result": result_data}

            elif status in ["Failed", "Canceled"]:
                error_info = result_data.get("error", {})
                logging.error(f"Analysis {status}: {error_info}")
                return {
                    "filename": filename,
                    "error": f"Analysis {status.lower()}: {error_info}",
                }
        else:
            logging.warning(
                f"Poll attempt {attempt + 1}: HTTP {result_response.status_code}"
            )

    logging.error("Timeout waiting for Content Understanding results")
    return {"filename": filename, "error": "Timeout waiting for results"}


def store_in_database(result: dict, server: str, database: str, token: str) -> dict:
    """Store the analysis results in Azure SQL Database."""
    logging.info(
        f"Connecting to SQL Database: {server}.database.windows.net/{database}"
    )

    # Encode token for pyodbc
    token_bytes = token.encode("UTF-16-LE")
    token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)

    conn_str = (
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server={server}.database.windows.net,1433;"
        f"Database={database};"
        f"Encrypt=yes;"
        f"TrustServerCertificate=no;"
    )

    try:
        conn = pyodbc.connect(conn_str, attrs_before={1256: token_struct})
        logging.info("Database connection established")
    except pyodbc.Error as e:
        logging.error(f"Database connection failed: {str(e)}")
        raise
    cursor = conn.cursor()

    # Insert contract
    cursor.execute(
        """
        INSERT INTO contracts (filename, title, duration, jurisdictions, dates, markdown, raw_fields)
        OUTPUT INSERTED.id
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            result.get("filename"),
            result.get("title"),
            result.get("duration"),
            json.dumps(result.get("jurisdictions", [])),
            json.dumps(result.get("dates", {})),
            result.get("markdown"),
            json.dumps(result.get("raw_fields", {})),
        ),
    )
    contract_id = cursor.fetchone()[0]

    # Insert parties
    party_ids = []
    for party in result.get("parties", []):
        cursor.execute(
            """
            INSERT INTO parties (contract_id, name, address, reference_name, clause)
            OUTPUT INSERTED.id
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                contract_id,
                party.get("name"),
                party.get("address"),
                party.get("reference_name"),
                party.get("clause"),
            ),
        )
        party_ids.append(cursor.fetchone()[0])

    # Insert clauses
    clause_ids = []
    for clause in result.get("clauses", []):
        cursor.execute(
            """
            INSERT INTO clauses (contract_id, clause_type, title, text)
            OUTPUT INSERTED.id
            VALUES (?, ?, ?, ?)
            """,
            (
                contract_id,
                clause.get("type"),
                clause.get("title"),
                clause.get("text"),
            ),
        )
        clause_ids.append(cursor.fetchone()[0])

    conn.commit()
    cursor.close()
    conn.close()

    return {
        "contract_id": contract_id,
        "party_ids": party_ids,
        "clause_ids": clause_ids,
    }


# ============================================================================
# Field Extraction Helpers
# ============================================================================


def extract_field_value(field_data):
    """Extract value from Content Understanding field structure."""
    if not field_data:
        return None

    field_type = field_data.get("type")

    if field_type == "array":
        return [extract_field_value(item) for item in field_data.get("valueArray", [])]
    elif field_type == "object":
        return {
            k: extract_field_value(v)
            for k, v in field_data.get("valueObject", {}).items()
        }
    elif field_type == "string":
        return field_data.get("valueString")
    elif field_type == "number":
        return field_data.get("valueNumber")
    elif field_type == "date":
        return field_data.get("valueDate")
    else:
        return field_data.get("content", field_data.get("valueString"))


def extract_array_field(field_data) -> list:
    """Extract array field values."""
    if not field_data:
        return []
    return [
        v
        for item in field_data.get("valueArray", [])
        if (v := extract_field_value(item)) is not None
    ]


def extract_parties(fields) -> list:
    """Extract party information from contract fields."""
    parties = []
    for party_item in fields.get("Parties", {}).get("valueArray", []):
        if party_item.get("type") == "object":
            party_obj = party_item.get("valueObject", {})
            party = {
                "name": extract_field_value(party_obj.get("Name")),
                "address": extract_field_value(party_obj.get("Address")),
                "reference_name": extract_field_value(party_obj.get("ReferenceName")),
                "clause": extract_field_value(party_obj.get("Clause")),
            }
            if party["name"]:
                parties.append({k: v for k, v in party.items() if v is not None})
    return parties


def extract_dates(fields) -> dict:
    """Extract date information from contract fields."""
    date_fields = ["ExecutionDate", "EffectiveDate", "ExpirationDate", "RenewalDate"]
    return {
        field: value
        for field in date_fields
        if (value := extract_field_value(fields.get(field)))
    }


def extract_clauses(fields) -> list:
    """Extract clause information from contract fields."""
    clauses = []
    for clause_item in fields.get("Clauses", {}).get("valueArray", []):
        if clause_item.get("type") == "object":
            clause_obj = clause_item.get("valueObject", {})
            clause = {
                "type": extract_field_value(clause_obj.get("clauseType")),
                "title": extract_field_value(clause_obj.get("clauseTitle")),
                "text": extract_field_value(clause_obj.get("clauseText")),
            }
            if clause["title"] or clause["text"]:
                clauses.append({k: v for k, v in clause.items() if v is not None})
    return clauses

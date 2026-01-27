"""
Azure Function for Contract Analysis using Azure Content Understanding.
Triggered via HTTP POST by Logic Apps.
"""

import azure.functions as func
import logging
import json
import time
import requests
from azure.identity import DefaultAzureCredential

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)


@app.route(route="analyze-contract", methods=["POST"])
def analyze_contract(req: func.HttpRequest) -> func.HttpResponse:
    """
    HTTP trigger function to analyze a contract document.

    Expects either:
    - Binary PDF content in request body with Content-Type: application/pdf
    - JSON body with base64-encoded PDF: {"filename": "contract.pdf", "content": "base64..."}

    Returns: JSON with extracted contract data
    """
    logging.info("Contract analysis function triggered")

    try:
        # Get configuration from environment or use defaults
        import os

        base_endpoint = os.environ.get(
            "CONTENT_UNDERSTANDING_ENDPOINT",
            "https://___-contracts-ai-proj-resource.cognitiveservices.azure.com",
        )
        api_version = os.environ.get("CONTENT_UNDERSTANDING_API_VERSION", "2025-11-01")
        analyzer_id = os.environ.get(
            "CONTENT_UNDERSTANDING_ANALYZER_ID", "projectAnalyzer_1768587228991_591"
        )

        endpoint = f"{base_endpoint}/contentunderstanding/analyzers/{analyzer_id}:analyzeBinary?api-version={api_version}"

        # Get authentication token
        credential = DefaultAzureCredential()
        token = credential.get_token("https://cognitiveservices.azure.com/.default")

        # Determine input format
        content_type = req.headers.get("Content-Type", "")

        if "application/pdf" in content_type:
            # Direct binary PDF upload
            file_content = req.get_body()
            filename = req.headers.get("X-Filename", "uploaded_contract.pdf")
        elif "application/json" in content_type:
            # JSON with base64-encoded content
            import base64

            body = req.get_json()
            filename = body.get("filename", "uploaded_contract.pdf")
            content_base64 = body.get("content", "")
            file_content = base64.b64decode(content_base64)
        else:
            # Try to parse as JSON first, fallback to binary
            try:
                import base64

                body = req.get_json()
                filename = body.get("filename", "uploaded_contract.pdf")
                content_base64 = body.get("content", "")
                file_content = base64.b64decode(content_base64)
            except:
                file_content = req.get_body()
                filename = req.headers.get("X-Filename", "uploaded_contract.pdf")

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
            token=token.token,
        )

        return func.HttpResponse(
            json.dumps(result, default=str),
            status_code=200,
            mimetype="application/json",
        )

    except Exception as e:
        logging.error(f"Error processing contract: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}), status_code=500, mimetype="application/json"
        )


@app.route(route="analyze-and-store", methods=["POST"])
def analyze_and_store(req: func.HttpRequest) -> func.HttpResponse:
    """
    HTTP trigger function to analyze a contract and store results in PostgreSQL.

    Expects either:
    - Binary PDF content in request body with Content-Type: application/pdf
    - JSON body with base64-encoded PDF: {"filename": "contract.pdf", "content": "base64..."}

    Returns: JSON with extracted contract data and database IDs
    """
    logging.info("Contract analysis and storage function triggered")

    try:
        import os
        import psycopg2

        # Get configuration
        base_endpoint = os.environ.get(
            "CONTENT_UNDERSTANDING_ENDPOINT",
            "https://___-contracts-ai-proj-resource.cognitiveservices.azure.com",
        )
        api_version = os.environ.get("CONTENT_UNDERSTANDING_API_VERSION", "2025-11-01")
        analyzer_id = os.environ.get(
            "CONTENT_UNDERSTANDING_ANALYZER_ID", "projectAnalyzer_1768587228991_591"
        )

        # Database configuration
        db_server = os.environ.get("POSTGRES_SERVER", "contract-db")
        db_name = os.environ.get("POSTGRES_DATABASE", "postgres")
        db_user = os.environ.get(
            "POSTGRES_USER", "admin@MngEnvMCAP560696.onmicrosoft.com"
        )

        endpoint = f"{base_endpoint}/contentunderstanding/analyzers/{analyzer_id}:analyzeBinary?api-version={api_version}"

        # Get authentication tokens
        credential = DefaultAzureCredential()
        cu_token = credential.get_token("https://cognitiveservices.azure.com/.default")
        pg_token = credential.get_token(
            "https://ossrdbms-aad.database.windows.net/.default"
        )

        # Determine input format
        content_type = req.headers.get("Content-Type", "")

        if "application/pdf" in content_type:
            file_content = req.get_body()
            filename = req.headers.get("X-Filename", "uploaded_contract.pdf")
        else:
            try:
                import base64

                body = req.get_json()
                filename = body.get("filename", "uploaded_contract.pdf")
                content_base64 = body.get("content", "")
                file_content = base64.b64decode(content_base64)
            except:
                file_content = req.get_body()
                filename = req.headers.get("X-Filename", "uploaded_contract.pdf")

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

        # Store in database
        host = f"{db_server}.postgres.database.azure.com"
        conn = psycopg2.connect(
            host=host,
            port=5432,
            database=db_name,
            user=db_user,
            password=pg_token.token,
            sslmode="require",
        )

        cursor = conn.cursor()

        # Insert contract
        cursor.execute(
            """
            INSERT INTO contracts (filename, title, duration, jurisdictions, dates, markdown, raw_fields)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            RETURNING id
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
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id
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
                VALUES (%s, %s, %s, %s)
                RETURNING id
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

        # Add database IDs to result
        result["database"] = {
            "contract_id": contract_id,
            "party_ids": party_ids,
            "clause_ids": clause_ids,
        }

        logging.info(
            f"Successfully stored contract {contract_id} with {len(party_ids)} parties and {len(clause_ids)} clauses"
        )

        return func.HttpResponse(
            json.dumps(result, default=str),
            status_code=200,
            mimetype="application/json",
        )

    except Exception as e:
        logging.error(f"Error processing contract: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}), status_code=500, mimetype="application/json"
        )


def analyze_contract_document(
    file_content: bytes, filename: str, endpoint: str, token: str
) -> dict:
    """
    Analyze a contract document using Azure Content Understanding.

    Args:
        file_content: Binary content of the PDF file
        filename: Name of the file being processed
        endpoint: Azure Content Understanding endpoint URL
        token: Bearer token for authentication

    Returns:
        Dictionary with extracted contract data
    """
    logging.info(f"Analyzing: {filename}")

    # Headers for binary upload
    binary_headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/pdf",
    }

    # Submit analysis request
    response = requests.post(endpoint, headers=binary_headers, data=file_content)

    if response.status_code != 202:
        logging.error(f"API error: {response.status_code} - {response.text}")
        return {
            "filename": filename,
            "error": f"API returned status {response.status_code}: {response.text}",
        }

    # Get the Operation-Location header for polling
    operation_location = response.headers.get("Operation-Location")

    if not operation_location:
        return {
            "filename": filename,
            "error": "No Operation-Location header in response",
        }

    # Poll for results
    poll_headers = {"Authorization": f"Bearer {token}"}
    max_retries = 60
    retry_count = 0

    while retry_count < max_retries:
        time.sleep(2)
        result_response = requests.get(operation_location, headers=poll_headers)

        if result_response.status_code == 200:
            result_data = result_response.json()
            status = result_data.get("status")

            if status == "Succeeded":
                result_contents = result_data.get("result", {}).get("contents", [])

                if result_contents:
                    content = result_contents[0]
                    fields = content.get("fields", {})

                    return {
                        "filename": filename,
                        "title": extract_contract_title(fields),
                        "parties": extract_parties(fields),
                        "dates": extract_dates(fields),
                        "duration": extract_duration(fields),
                        "jurisdictions": extract_jurisdictions(fields),
                        "clauses": extract_clauses(fields),
                        "raw_fields": fields,
                        "markdown": content.get("markdown", ""),
                    }
                else:
                    return {"filename": filename, "raw_result": result_data}

            elif status in ["Failed", "Canceled"]:
                error_info = result_data.get("error", {})
                return {
                    "filename": filename,
                    "error": f"Analysis {status.lower()}: {error_info}",
                }

        retry_count += 1

    return {"filename": filename, "error": "Timeout waiting for analysis results"}


# ============================================================================
# Field Extraction Helper Functions
# ============================================================================


def extract_field_value(field_data):
    """Extract values from Content Understanding field structure."""
    if not field_data:
        return None

    field_type = field_data.get("type")

    if field_type == "array":
        return [extract_field_value(item) for item in field_data.get("valueArray", [])]
    elif field_type == "object":
        obj = {}
        for key, value in field_data.get("valueObject", {}).items():
            obj[key] = extract_field_value(value)
        return obj
    elif field_type == "string":
        return field_data.get("valueString")
    elif field_type == "number":
        return field_data.get("valueNumber")
    elif field_type == "date":
        return field_data.get("valueDate")
    else:
        return field_data.get("content", field_data.get("valueString"))


def extract_contract_title(fields):
    """Extract contract title from fields."""
    return extract_field_value(fields.get("Title"))


def extract_parties(fields):
    """Extract party information from contract fields."""
    parties = []
    parties_field = fields.get("Parties", {})
    parties_array = parties_field.get("valueArray", [])

    for party_item in parties_array:
        if party_item.get("type") == "object":
            party_obj = party_item.get("valueObject", {})

            party_data = {
                "name": extract_field_value(party_obj.get("Name")),
                "address": extract_field_value(party_obj.get("Address")),
                "reference_name": extract_field_value(party_obj.get("ReferenceName")),
                "clause": extract_field_value(party_obj.get("Clause")),
            }

            if party_data["name"]:
                party_data = {k: v for k, v in party_data.items() if v is not None}
                parties.append(party_data)

    return parties


def extract_dates(fields):
    """Extract date information from contract fields."""
    dates = {}
    date_fields = ["ExecutionDate", "EffectiveDate", "ExpirationDate", "RenewalDate"]

    for date_field in date_fields:
        date_value = extract_field_value(fields.get(date_field))
        if date_value:
            dates[date_field] = date_value

    return dates


def extract_duration(fields):
    """Extract contract duration from fields."""
    return extract_field_value(fields.get("ContractDuration"))


def extract_jurisdictions(fields):
    """Extract jurisdiction information from contract fields."""
    jurisdictions_field = fields.get("Jurisdictions", {})
    jurisdictions_array = jurisdictions_field.get("valueArray", [])

    jurisdictions = []
    for item in jurisdictions_array:
        value = extract_field_value(item)
        if value:
            jurisdictions.append(value)

    return jurisdictions


def extract_clauses(fields):
    """Extract clause information from contract fields."""
    clauses = []
    clauses_field = fields.get("Clauses", {})
    clauses_array = clauses_field.get("valueArray", [])

    for clause_item in clauses_array:
        if clause_item.get("type") == "object":
            clause_obj = clause_item.get("valueObject", {})

            clause_data = {
                "type": extract_field_value(clause_obj.get("clauseType")),
                "title": extract_field_value(clause_obj.get("clauseTitle")),
                "text": extract_field_value(clause_obj.get("clauseText")),
            }

            if clause_data["title"] or clause_data["text"]:
                clause_data = {k: v for k, v in clause_data.items() if v is not None}
                clauses.append(clause_data)

    return clauses

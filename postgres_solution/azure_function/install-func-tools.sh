#!/bin/bash
# Install Azure Functions Core Tools v4
# Usage: ./install-func-tools.sh

set -e

echo "🔧 Installing Azure Functions Core Tools v4..."

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Detected: Linux"
    
    # Check for Ubuntu/Debian
    if command -v apt-get &> /dev/null; then
        echo "Installing via apt..."
        curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
        sudo mv microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg
        sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-ubuntu-$(lsb_release -cs)-prod $(lsb_release -cs) main" > /etc/apt/sources.list.d/dotnetdev.list'
        sudo apt-get update
        sudo apt-get install -y azure-functions-core-tools-4
    # Check for Fedora/RHEL
    elif command -v dnf &> /dev/null; then
        echo "Installing via dnf..."
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
        sudo dnf install -y azure-functions-core-tools-4
    else
        echo "❌ Unsupported Linux distribution. Please install manually."
        exit 1
    fi

elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Detected: macOS"
    
    if command -v brew &> /dev/null; then
        echo "Installing via Homebrew..."
        brew tap azure/functions
        brew install azure-functions-core-tools@4
    else
        echo "❌ Homebrew not found. Please install Homebrew first: https://brew.sh"
        exit 1
    fi

else
    echo "❌ Unsupported OS: $OSTYPE"
    echo "Please install manually: https://learn.microsoft.com/azure/azure-functions/functions-run-local"
    exit 1
fi

# Verify installation
if command -v func &> /dev/null; then
    echo ""
    echo "✅ Azure Functions Core Tools installed successfully!"
    func --version
else
    echo "❌ Installation may have failed. Please check the output above."
    exit 1
fi

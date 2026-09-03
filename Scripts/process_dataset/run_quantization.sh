#!/bin/bash
# Shell script to automate the quantization pipeline for all sensor domains (Q9.15 only)

INPUT_BASE="dataset_split"
Q915_BASE="dataset_q915"

DOMAINS=("vibration" "temperature" "current")

echo "Starting Batch Quantization Pipeline..."

for DOMAIN in "${DOMAINS[@]}"; do
    DOMAIN_INPUT="$INPUT_BASE/$DOMAIN"
    
    if [ -d "$DOMAIN_INPUT" ]; then
        echo "============================================================"
        echo "Quantizing Domain: $DOMAIN"
        echo "============================================================"
        
        python3 quantize.py \
            --input "$DOMAIN_INPUT" \
            --output-q915 "$Q915_BASE/$DOMAIN"
            
        if [ $? -ne 0 ]; then
            echo "ERROR: Quantization failed for $DOMAIN. Exiting."
            exit 1
        fi
    else
        echo "Skipping $DOMAIN: Input directory $DOMAIN_INPUT not found."
    fi
done

echo "============================================================"
echo "All domains quantized successfully."

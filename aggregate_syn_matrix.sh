#!/bin/bash

IDENTIFIER=$1

if [ -z "$IDENTIFIER" ]; then
    echo "Usage: ./aggregate_syn_matrix.sh <identifier>"
    exit 1
fi

DERIV_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration"
OUT_DIR="${DERIV_DIR}/${IDENTIFIER}"
MATRIX_FILE="${OUT_DIR}/correlation_matrix_SyN_${IDENTIFIER}.txt"

if [ ! -d "$OUT_DIR" ]; then
    echo "Error: Directory $OUT_DIR not found."
    exit 1
fi

> "$MATRIX_FILE"
NUM_SES=7

echo "Aggregating matrix for $IDENTIFIER..."

for (( i=0; i<$NUM_SES; i++ )); do
    ROW_OUTPUT=""
    for (( j=0; j<$NUM_SES; j++ )); do
        
        TEMP_FILE="${OUT_DIR}/tmp_corr_SyN_${i}_${j}.txt"
        
        if [ -f "$TEMP_FILE" ]; then
            CORR=$(cat "$TEMP_FILE")
        else
            CORR="NaN" # Fallback if the array task completely failed
        fi
        
        ROW_OUTPUT="$ROW_OUTPUT $CORR"
        
    done
    echo "$ROW_OUTPUT" >> "$MATRIX_FILE"
done

echo "Matrix successfully built at: $MATRIX_FILE"

# Clean up the temporary array files to keep the folder neat
rm "${OUT_DIR}"/tmp_corr_SyN_*.txt 2>/dev/null
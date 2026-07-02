#!/bin/bash

ml ants
ml fsl

# Check if an identifier was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <file_identifier>"
    echo "Example: $0 mp2rage_0p7iso_PS_UNI-DEN"
    exit 1
fi

IDENTIFIER="$1"

# Define your input and output base paths
BASE_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/orig"
DERIV_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration"

# Create a specific output directory named after the scan ID
OUT_DIR="${DERIV_DIR}/${IDENTIFIER}"
mkdir -p "$OUT_DIR"

# Defined chronological sessions
SESSION_DIRS=(
    "260529_THS_ses01"
    "260601_THS_ses02"
    "260602_THS_ses03"
    "260611_THS_ses05"
    "260618_THS_ses06"
    "260618_THS_ses07"
)

# Regex to match the exact file
REGEX_PATTERN="${IDENTIFIER}_[0-9]+\.nii(\.gz)?$"

FOUND_FILES=()
VALID_SESSIONS=()

echo "Searching for '$IDENTIFIER' in $BASE_DIR..."

for ses in "${SESSION_DIRS[@]}"; do
    search_path="${BASE_DIR}/${ses}"
    
    if [ ! -d "$search_path" ]; then
        echo "  [Skipping] Directory not found: $ses"
        continue
    fi
    
    TARGET_FILE=$(find "$search_path" -maxdepth 1 -type f | grep -E "$REGEX_PATTERN" | head -n 1)
    
    if [[ -n "$TARGET_FILE" && -f "$TARGET_FILE" ]]; then
        FOUND_FILES+=("$TARGET_FILE")
        VALID_SESSIONS+=("$ses")
        echo "  [Found] $ses -> $(basename "$TARGET_FILE")"
    else
        echo "  [Skipping] No matching file found in $ses"
    fi
done

NUM_VALID=${#FOUND_FILES[@]}

if [ "$NUM_VALID" -lt 2 ]; then
    echo ""
    echo "Error: Found less than 2 valid sessions ($NUM_VALID). Cannot compute a correlation matrix."
    exit 1
fi

echo ""
echo "Proceeding with $NUM_VALID sessions."
echo "All outputs will be saved to: $OUT_DIR"
echo "------------------------------------------------------"

TRANSFORM_FLAGS=("r" "a")
TRANSFORM_NAMES=("Rigid" "Affine")
NUM_TRANSFORMS=${#TRANSFORM_FLAGS[@]}

for (( t=0; t<$NUM_TRANSFORMS; t++ )); do
    FLAG="${TRANSFORM_FLAGS[$t]}"
    NAME="${TRANSFORM_NAMES[$t]}"
    
    # Route the matrix file to the new output directory
    MATRIX_FILE="${OUT_DIR}/correlation_matrix_${NAME}_${IDENTIFIER}.txt"
    > "$MATRIX_FILE"
    
    echo ""
    echo "========================================="
    echo " Executing $NAME Transformations (-t $FLAG)"
    echo "========================================="
    
    for (( i=0; i<$NUM_VALID; i++ )); do
        ROW_OUTPUT=""
        
        for (( j=0; j<$NUM_VALID; j++ )); do
            MOVING="${FOUND_FILES[$i]}"
            FIXED="${FOUND_FILES[$j]}"
            
            MOV_SES="${VALID_SESSIONS[$i]}"
            FIX_SES="${VALID_SESSIONS[$j]}"
            
            # Route the ANTs outputs to the new directory
            OUT_PREFIX="${OUT_DIR}/reg_${NAME}_mov_${MOV_SES}_to_fix_${FIX_SES}_"
            
            if [ $i -eq $j ]; then
                echo "  [${NAME}] Self-registering ${MOV_SES}..."
            else
                echo "  [${NAME}] Registering ${MOV_SES} to ${FIX_SES}..."
            fi
            
            # 1. Register
            antsRegistrationSyNQuick.sh -d 3 -f "$FIXED" -m "$MOVING" -o "$OUT_PREFIX" -t "$FLAG"
            
            REGISTERED_IMG="${OUT_PREFIX}Warped.nii.gz"
            
            # 2. Compute correlation
            if [ -f "$REGISTERED_IMG" ]; then
                CORR=$(fslcc "$FIXED" "$REGISTERED_IMG" | awk '{print $3}')
            else
                CORR="ERR"
            fi
            
            ROW_OUTPUT="$ROW_OUTPUT $CORR"
        done
        
        # Save the row
        echo "$ROW_OUTPUT" >> "$MATRIX_FILE"
    done
    
    echo ""
    echo "=== Final Matrix: $NAME ($IDENTIFIER) ==="
    echo "Row/Col Order: ${VALID_SESSIONS[*]}"
    echo "Saved in: $OUT_DIR"
    echo "------------------------------------------------------"
    column -t "$MATRIX_FILE"
done
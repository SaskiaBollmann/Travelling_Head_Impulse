#!/bin/bash

# Check if an identifier was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <file_identifier>"
    echo "Example: $0 mp2rage_0p7iso_PS_UNI-DEN"
    exit 1
fi

IDENTIFIER="$1"
BASE_DIR="/oak/stanford/groups/polimeni/saskia/data/THS_2026/orig"

# Defined chronological sessions (including all 7 listed)
SESSION_DIRS=(
    "260529_THS_ses01"
    "260601_THS_ses02"
    "260602_THS_ses03"
    "260602_THS_ses04"
    "260611_THS_ses05"
    "260618_THS_ses06"
    "260618_THS_ses07"
)

# Regex breakdown:
# - Matches exactly the identifier
# - Followed by an underscore and one or more digits: _[0-9]+
# - Ends exactly with .nii or .nii.gz: \.nii(\.gz)?$
REGEX_PATTERN="${IDENTIFIER}_[0-9]+\.nii(\.gz)?$"

# Arrays to hold the successfully located files and their parent sessions
FOUND_FILES=()
VALID_SESSIONS=()

echo "Searching for '$IDENTIFIER' in $BASE_DIR..."

for ses in "${SESSION_DIRS[@]}"; do
    search_path="${BASE_DIR}/${ses}"
    
    if [ ! -d "$search_path" ]; then
        echo "  [Skipping] Directory not found: $ses"
        continue
    fi
    
    # Use find and grep to locate the exact file matching our regex
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
echo "------------------------------------------------------"

# Define the local transformation parameters
TRANSFORM_FLAGS=("r" "a")
TRANSFORM_NAMES=("Rigid" "Affine")
NUM_TRANSFORMS=${#TRANSFORM_FLAGS[@]}

for (( t=0; t<$NUM_TRANSFORMS; t++ )); do
    FLAG="${TRANSFORM_FLAGS[$t]}"
    NAME="${TRANSFORM_NAMES[$t]}"
    MATRIX_FILE="correlation_matrix_${NAME}_${IDENTIFIER}.txt"
    
    # Clear out any existing matrix file for this run
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
            
            # Use session names for output prefixes instead of array indices
            MOV_SES="${VALID_SESSIONS[$i]}"
            FIX_SES="${VALID_SESSIONS[$j]}"
            
            OUT_PREFIX="reg_${NAME}_mov_${MOV_SES}_to_fix_${FIX_SES}_"
            
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
    echo "------------------------------------------------------"
    column -t "$MATRIX_FILE"
done
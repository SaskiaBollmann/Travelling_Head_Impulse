#!/bin/bash
#SBATCH --job-name=ants_n4       
#SBATCH --output=ants_n4.%j.out  
#SBATCH --error=ants_n4.%j.err   
#SBATCH --time=4:00:00              
#SBATCH --partition=owners        
#SBATCH --cpus-per-task=4         
#SBATCH --mem=32GB

#SBATCH -o /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/biasfield/ants_refine_nd-%j.output
#SBATCH -e /oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/biasfield/ants_refine_nd-%j.error

# Load necessary modules
ml ants

# Exit immediately if a command exits with a non-zero status
set -e
# --- 1. ARGUMENT PARSING ---
RAW_ID="$1"

if [ -z "$RAW_ID" ]; then
    echo "Error: You must provide a session ID."
    echo "Usage: sbatch $0 <session_id>"
    exit 1
fi

# --- 2. DIRECTORY SETUP ---
BASE_DIR="$HOME/oak_data/THS_2026"
INPUT_DIR="${BASE_DIR}/orig/${RAW_ID}"

# --- UPDATED: Output directory now includes the session ID as a subfolder ---
OUTPUT_DIR="${BASE_DIR}/derivatives/biasfield/${RAW_ID}"

if [ ! -d "$INPUT_DIR" ]; then
    echo "Error: Input directory $INPUT_DIR does not exist."
    exit 1
fi

# This will create the derivatives/biasfield folder AND the session subfolder inside it
mkdir -p "$OUTPUT_DIR"

echo "=================================================="
echo " Starting Resumable Unmasked MP2RAGE N4 Loop"
echo " Session ID: $RAW_ID"
echo " Input Dir:  $INPUT_DIR"
echo " Output Dir: $OUTPUT_DIR"
echo "=================================================="

# --- 3. FUNCTION DEFINITION ---
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=$SLURM_CPUS_PER_TASK

run_n4() {
    local img_path="$1"
    local prefix="$2"
    
    local basename=$(basename "$img_path")
    basename="${basename%.nii.gz}"
    basename="${basename%.nii}"
    
    local corrected_out="${OUTPUT_DIR}/${RAW_ID}_${basename}_N4corrected.nii.gz"
    local bias_out="${OUTPUT_DIR}/${RAW_ID}_${basename}_biasfield.nii.gz"

    # --- SKIP CHECK ---
    if [ -f "$corrected_out" ] && [ -f "$bias_out" ]; then
        echo "Skipping: Outputs already exist for ${RAW_ID}_${basename}"
        echo "--------------------------------------------------"
        return
    fi

echo "Processing N4 (Unmasked, B-Spline 150) for: ${RAW_ID}_${basename}"

    N4BiasFieldCorrection \
        -d 3 \
        -i "$img_path" \
        -s 2 \
        -c [50x50x50x50,0.000001] \
        -b [150] \
        -o ["$corrected_out","$bias_out"] \
        -v 1
        
    echo "Saved Corrected Image to: $corrected_out"
    echo "Saved Bias Field to:      $bias_out"
    echo "--------------------------------------------------"
}

# --- 4. FILE DISCOVERY & EXECUTION LOOP ---
# Enable case-insensitive and null globbing
shopt -s nocaseglob nullglob

# Create arrays of all matching files
INV2_FILES=("$INPUT_DIR"/*INV2*ND*.nii*)
UNI_FILES=("$INPUT_DIR"/*UNI*ND*.nii*)

# Disable globbing options
shopt -u nocaseglob nullglob

# Check if we found anything at all
if [ ${#INV2_FILES[@]} -eq 0 ] && [ ${#UNI_FILES[@]} -eq 0 ]; then
    echo "Error: No INV2_ND or UNI_ND files found in $INPUT_DIR."
    exit 1
fi

# Loop over all found INV2_ND files
if [ ${#INV2_FILES[@]} -gt 0 ]; then
    echo "Found ${#INV2_FILES[@]} INV2_ND file(s). Starting processing..."
    for img in "${INV2_FILES[@]}"; do
        # Ignore any files that contain 'facemask'
        if [[ "$img" == *facemask* ]]; then
            echo "Skipping facemask image: $(basename "$img")"
            continue
        fi
        run_n4 "$img" "INV2_ND"
    done
else
    echo "Warning: No INV2_ND files found."
fi

# Loop over all found UNI-DEN_ND files
if [ ${#UNI_FILES[@]} -gt 0 ]; then
    echo "Found ${#UNI_FILES[@]} UNI-DEN_ND file(s). Starting processing..."
    for img in "${UNI_FILES[@]}"; do
        # Ignore any files that contain 'facemask'
        if [[ "$img" == *facemask* ]]; then
            echo "Skipping facemask image: $(basename "$img")"
            continue
        fi
        run_n4 "$img" "UNI-DEN_ND"
    done
else
    echo "Warning: No UNI-DEN_ND files found."
fi

echo "=================================================="
echo " Job Complete!"
echo "=================================================="
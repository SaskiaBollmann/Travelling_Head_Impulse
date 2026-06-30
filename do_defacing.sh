#!/bin/bash

# Create the output directories for the defaced files and QC screenshots
mkdir -p defaced qc

# Loop through only the UNI-DEN .nii files
for uni_den in *UNI-DEN*.nii; do
  echo "=================================================="
  echo "Processing batch for reference: $uni_den"

  facemask="${uni_den%.nii}_facemask.nii"

  echo "Generating facemask: $facemask"
  mideface --i "$uni_den" \
           --o "defaced/$uni_den" \
           --facemask "$facemask"
           
  # Generate a QC screenshot of the UNI-DEN image
  slicer "defaced/$uni_den" -a "qc/${uni_den%.nii}_qc.png"

  # Loop through all MP2RAGE files
  for img in *mp2rage*.nii; do
    
    # 1. Skip the facemask and the UNI-DEN file we just defaced
    if [[ "$img" == *"$facemask"* ]] || [[ "$img" == "$uni_den" ]]; then 
      continue 
    fi

    # 2. STRICT BATCH MATCHING
    # If reference is TrueForm, target MUST be TrueForm
    if [[ "$uni_den" == *"TrueForm"* ]] && [[ "$img" != *"TrueForm"* ]]; then 
      continue 
    fi
    # If reference is patientSpecific, target MUST be patientSpecific
    if [[ "$uni_den" == *"patientSpecific"* ]] && [[ "$img" != *"patientSpecific"* ]]; then 
      continue 
    fi
    # Match _ND_ (Noise Denoised) exactly
    if [[ "$uni_den" == *"_ND_"* ]] && [[ "$img" != *"_ND_"* ]]; then 
      continue 
    fi
    if [[ "$uni_den" != *"_ND_"* ]] && [[ "$img" == *"_ND_"* ]]; then 
      continue 
    fi

    # 3. APPLY DEFACING TO EVERYTHING THAT MATCHES
    echo "  -> Applying mask to matching file: $img"
    mideface --apply "$img" "$facemask" regheader "defaced/$img"
    
    # Generate a QC screenshot of the applied defacing
    slicer "defaced/$img" -a "qc/${img%.nii}_qc.png"
    
  done
done

echo "=================================================="
echo "Done! All files have been defaced and screenshots are waiting in the 'qc/' folder."

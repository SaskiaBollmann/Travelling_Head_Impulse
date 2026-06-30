#!/bin/bash

# Create the output directories
mkdir -p defaced qc

# 1. Loop through ONLY the ND versions of the UNI-DEN images
for uni_den in *UNI-DEN_ND*.nii; do
  echo "=================================================="
  echo "Processing reference image: $uni_den"

  # 2. Determine which batch this reference belongs to
  batch_id=""
  if [[ "$uni_den" == *"TrueForm"* ]]; then
    batch_id="TrueForm"
  elif [[ "$uni_den" == *"patientSpecific"* ]]; then
    batch_id="patientSpecific"
  else
    echo "Warning: Could not identify batch for $uni_den. Skipping."
    continue
  fi

  facemask="${uni_den%.nii}_facemask.nii"

  # 3. Generate the mask using ONLY the clean ND image
  echo "Generating facemask from ND image: $facemask"
  mideface --i "$uni_den" \
           --o "defaced/$uni_den" \
           --facemask "$facemask"
           
  slicer "defaced/$uni_den" -a "qc/${uni_den%.nii}_qc.png"

  # 4. Loop through ALL files that belong to this specific batch (both ND and non-ND)
  # The wildcard *${batch_id}* ensures it only grabs files for the current batch
  for img in *mp2rage*${batch_id}*.nii; do
    
    # Skip the facemask we just generated and the reference image we just defaced
    if [[ "$img" == *"$facemask"* ]] || [[ "$img" == "$uni_den" ]]; then 
      continue 
    fi

    # 5. Apply the ND mask to the image (whether it is ND or not)
    echo "  -> Applying ND mask to: $img"
    mideface --apply "$img" "$facemask" regheader "defaced/$img"
    
    slicer "defaced/$img" -a "qc/${img%.nii}_qc.png"
    
  done
done

echo "=================================================="
echo "Done! All MP2RAGE images defaced using their respective ND masks."

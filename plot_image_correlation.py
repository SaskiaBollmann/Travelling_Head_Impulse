#!/usr/bin/env python3

import sys
import os
import glob
import numpy as np
import seaborn as sns
import matplotlib.pyplot as plt

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 plot_matrices.py <folder_name>")
        sys.exit(1)

    folder_name = sys.argv[1]
    
    base_deriv_dir = "/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration"
    target_dir = os.path.join(base_deriv_dir, folder_name)

    if not os.path.isdir(target_dir):
        print(f"Error: Directory '{target_dir}' does not exist.")
        sys.exit(1)

    search_pattern = os.path.join(target_dir, "*.txt")
    matrix_files = glob.glob(search_pattern)

    if not matrix_files:
        print(f"No text matrices found in '{target_dir}'.")
        sys.exit(1)

    print(f"Found {len(matrix_files)} matrix file(s) for '{folder_name}'. Generating plots...")

    for file_path in matrix_files:
        filename = os.path.basename(file_path)
        transform_name = filename.replace("correlation_matrix_", "").replace(f"_{folder_name}.txt", "")

        try:
            # Load string matrix, converting "NaN" strings back to np.nan so seaborn can handle them gracefully
            matrix = np.genfromtxt(file_path, missing_values="NaN", filling_values=np.nan)
        except Exception as e:
            print(f"  [Skipping] Failed to load {filename}: {e}")
            continue

        num_sessions = matrix.shape[0]
        
        # Calculate dynamic minimum safely ignoring NaNs and perfect 1.0 correlations
        valid_vals = matrix[(matrix < 0.999) & (~np.isnan(matrix))]
        off_diag_min = np.nanmin(valid_vals) if valid_vals.size > 0 else 0.95
        
        labels = []
        for i in range(num_sessions):
            ses_num = f"{i+1:02d}"
            if i < 3:
                labels.append(f"Stanford\nSes {ses_num}")
            else:
                labels.append(f"Magdeburg\nSes {ses_num}")
        
        plt.figure(figsize=(9, 7))
        
        ax = sns.heatmap(matrix, annot=True, fmt=".3f", cmap="viridis",
                         vmin=off_diag_min, vmax=1.00,
                         xticklabels=labels, yticklabels=labels,
                         linewidths=0.5, linecolor='black')

        if num_sessions >= 4:
            ax.axhline(3, color='white', linewidth=3)
            ax.axvline(3, color='white', linewidth=3)

        plt.title(f"Cross-Session Correlation: {transform_name}\n({folder_name})", pad=15)
        plt.xticks(rotation=45, ha='right')
        plt.yticks(rotation=0)
        plt.tight_layout()

        output_filename = file_path.replace('.txt', '.png')
        plt.savefig(output_filename, dpi=300)
        plt.close() 
        
        print(f"  -> Saved {os.path.basename(output_filename)}")

if __name__ == "__main__":
    main()
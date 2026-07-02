#!/usr/bin/env python3

import sys
import os
import glob
import numpy as np
import seaborn as sns
import matplotlib.pyplot as plt

def main():
    # Ensure an identifier was passed as an argument
    if len(sys.argv) < 2:
        print("Usage: python3 plot_matrices.py <scan_identifier>")
        print("Example: python3 plot_matrices.py dzne_b1map_5iso_sag_B1Comb")
        sys.exit(1)

    identifier = sys.argv[1]
    
    # Define the base derivatives directory to match the bash script
    base_deriv_dir = "/oak/stanford/groups/polimeni/saskia/data/THS_2026/derivatives/coregistration"
    target_dir = os.path.join(base_deriv_dir, identifier)

    if not os.path.isdir(target_dir):
        print(f"Error: Directory '{target_dir}' does not exist.")
        sys.exit(1)

    # Find all text files in the target directory
    search_pattern = os.path.join(target_dir, "*.txt")
    matrix_files = glob.glob(search_pattern)

    if not matrix_files:
        print(f"No text matrices found in '{target_dir}'.")
        sys.exit(1)

    print(f"Found {len(matrix_files)} matrix file(s) for '{identifier}'. Generating plots...")

    # Loop through each found file and plot it
    for file_path in matrix_files:
        filename = os.path.basename(file_path)
        
        # Extract the transformation name (e.g., Rigid, Affine, SyN) for a cleaner title
        # Assuming format: correlation_matrix_Rigid_identifier.txt
        transform_name = filename.replace("correlation_matrix_", "").replace(f"_{identifier}.txt", "")

        try:
            matrix = np.loadtxt(file_path)
        except Exception as e:
            print(f"  [Skipping] Failed to load {filename}: {e}")
            continue

        num_sessions = matrix.shape[0]
        
        # Dynamically set the color limits based on the data to maximize contrast
        # (Ignoring the 1.0 diagonal so it doesn't skew the minimum)
        off_diag_min = np.min(matrix[matrix < 0.999]) if np.any(matrix < 0.999) else 0.95

        # Create the grouped labels with swapped order and leading zeros
        labels = []
        for i in range(num_sessions):
            ses_num = f"{i+1:02d}"
            if i < 3:
                labels.append(f"(Stanford)\nSes {ses_num}")
            else:
                labels.append(f"(Magdeburg)\nSes {ses_num}")
        
        # Initialize the plot 
        plt.figure(figsize=(9, 7))
        
        # Heatmap using the dynamic off_diag_min
        ax = sns.heatmap(matrix, annot=True, fmt=".3f", cmap="viridis",
                         vmin=off_diag_min, vmax=1.00,
                         xticklabels=labels, yticklabels=labels,
                         linewidths=0.5, linecolor='black')

        # Add a thicker white dividing line between session 3 and 4 
        if num_sessions >= 4:
            ax.axhline(3, color='white', linewidth=3)
            ax.axvline(3, color='white', linewidth=3)

        # Formatting
        plt.title(f"Cross-Session Correlation: {transform_name}\n({identifier})", pad=15)
        plt.xticks(rotation=45, ha='right')
        plt.yticks(rotation=0)
        plt.tight_layout()

        # Save the output as a high-res PNG next to the text file
        output_filename = file_path.replace('.txt', '.png')
        plt.savefig(output_filename, dpi=300)
        plt.close() # Close the figure to free up memory before the next loop iteration
        
        print(f"  -> Saved {os.path.basename(output_filename)}")

    print("All plots generated successfully.")

if __name__ == "__main__":
    main()
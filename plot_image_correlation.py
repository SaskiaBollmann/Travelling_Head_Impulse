#!/usr/bin/env python3

import sys
import os
import numpy as np
import seaborn as sns
import matplotlib.pyplot as plt

def main():
    # Ensure a file was passed as an argument
    if len(sys.argv) < 2:
        print("Usage: python3 plot_image_correlation.py <path_to_matrix.txt>")
        sys.exit(1)

    file_path = sys.argv[1]
    
    if not os.path.exists(file_path):
        print(f"Error: File '{file_path}' not found.")
        sys.exit(1)

    # Load the matrix from the text file
    try:
        matrix = np.loadtxt(file_path)
    except Exception as e:
        print(f"Failed to load matrix: {e}")
        sys.exit(1)

    num_sessions = matrix.shape[0]
    
    # Create the grouped labels for Stanford (1-3) and Magdeburg (4-6+)
    labels = []
    for i in range(num_sessions):
        if i < 3:
            labels.append(f"Ses {i+1}\nStanford")
        else:
            labels.append(f"Ses {i+1}\nMagdeburg)")
    
    # Initialize the plot (slightly larger to accommodate the multi-line labels)
    plt.figure(figsize=(9, 7))
    
    # Create the heatmap with a fixed color range of 0.9 to 1.0
    ax = sns.heatmap(matrix, annot=True, fmt=".3f", cmap="viridis",
                     vmin=0.90, vmax=1.00,
                     xticklabels=labels, yticklabels=labels,
                     linewidths=0.5, linecolor='black')

    # Add a thicker white dividing line between session 3 and 4 
    # (Index 3 separates the first 3 sessions from the rest)
    if num_sessions >= 4:
        ax.axhline(3, color='white', linewidth=3)
        ax.axvline(3, color='white', linewidth=3)

    # Formatting
    plt.title(f"Cross-Session Correlation\n({os.path.basename(file_path)})", pad=15)
    plt.xticks(rotation=45, ha='right')
    plt.yticks(rotation=0)
    plt.tight_layout()

    # Save the output as a high-res PNG next to the original text file
    output_filename = file_path.replace('.txt', '.png')
    plt.savefig(output_filename, dpi=300)
    print(f"Saved heatmap to: {output_filename}")

if __name__ == "__main__":
    main()
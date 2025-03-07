import re
import numpy as np
import matplotlib.pyplot as plt

def parse_results(file_path):
    """
    Parses the evaluation file and returns a nested dictionary with structure:
      results[dataset][approach] = { 'rmse': value, 'mean': value, ... }
    """
    results = {}
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Split the content by blocks separated by a line of "=" characters.
    blocks = re.split(r"=+\n", content)
    
    # Pattern to match header lines like:
    # "Evaluation results for dataset: fr1_room (ORB-SLAM3)"
    header_pattern = re.compile(r"Evaluation results for dataset:\s*([^\(]+)\s*\(([^)]+)\)")
    
    # Pattern to capture metrics lines like:
    # "absolute_translational_error.rmse 0.069617 m"
    metric_pattern = re.compile(r"absolute_translational_error\.(\w+)\s+([\d\.]+) m")
    
    for block in blocks:
        header_match = header_pattern.search(block)
        if header_match:
            dataset = header_match.group(1).strip()
            approach = header_match.group(2).strip()
            if dataset not in results:
                results[dataset] = {}
            metrics = {}
            for metric_match in metric_pattern.finditer(block):
                metric_name = metric_match.group(1)
                metric_value = float(metric_match.group(2))
                metrics[metric_name] = metric_value
            results[dataset][approach] = metrics
    return results

def plot_rmse(results):
    """
    Plots a grouped bar chart for the RMSE values for each dataset and approach.
    """
    # Get sorted list of datasets and list of approaches.
    datasets = sorted(results.keys())
    approaches = set()
    for dataset in datasets:
        for app in results[dataset]:
            approaches.add(app)
    approaches = sorted(list(approaches))
    
    # Prepare data array: each row for an approach, each column for a dataset.
    n_datasets = len(datasets)
    n_approaches = len(approaches)
    rmse_data = np.zeros((n_approaches, n_datasets))
    
    for j, approach in enumerate(approaches):
        for i, dataset in enumerate(datasets):
            # Use NaN if a given approach is not available for the dataset.
            rmse = results[dataset].get(approach, {}).get('rmse', np.nan)
            rmse_data[j, i] = rmse
    
    # Setup bar positions.
    ind = np.arange(n_datasets)
    width = 0.8 / n_approaches  # total group width is 0.8
    
    fig, ax = plt.subplots(figsize=(10, 6))
    for j, approach in enumerate(approaches):
        ax.bar(ind + j*width, rmse_data[j, :], width, label=approach)
    
    ax.set_ylabel('RMSE (m)')
    ax.set_title('Absolute Translational Error RMSE by Dataset and Approach')
    ax.set_xticks(ind + width*(n_approaches-1)/2)
    ax.set_xticklabels(datasets, rotation=45)
    ax.legend(title="Approach")
    plt.tight_layout()
    plt.show()

def main():
    file_path = "slam_eval_results.txt"
    results = parse_results(file_path)
    # Print parsed results for verification
    for dataset, approaches in results.items():
        print(f"{dataset}:")
        for approach, metrics in approaches.items():
            print(f"  {approach}: {metrics}")
    plot_rmse(results)

if __name__ == "__main__":
    main()

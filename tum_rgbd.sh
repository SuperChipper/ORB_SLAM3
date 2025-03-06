#!/bin/bash

###############################################################################
# Function to check if a dataset exists, and download it if not
###############################################################################
download_dataset() {
    local dataset_url=$1
    local dataset_name=$2
    local dataset_dir=$3

    if [ ! -d "$dataset_dir" ]; then
        echo "Dataset not found. Downloading $dataset_name..."
        mkdir -p "$dataset_dir"
        wget -O "$dataset_dir/$dataset_name.tgz" "$dataset_url"
        echo "Download complete!"
    else
        echo "Dataset $dataset_name already exists."
    fi
}

###############################################################################
# Function to evaluate results and save them into a file
###############################################################################
evaluate_results() {
    local groundtruth_file=$1
    local results_file=$2
    local eval_file=$3

    echo "Evaluating results..." | tee -a "$eval_file"
    python3 ./evaluation/evaluate_ate_scale.py "$groundtruth_file" "$results_file" --verbose 2>&1 | tee -a "$eval_file"
    echo "Evaluation complete!" | tee -a "$eval_file"
}


###############################################################################
# Function to run ORB-SLAM3 and PRIOR-SLAM on a dataset, measuring runtime
###############################################################################
run_orbslam3() {
    local dataset_path=$1
    local vocab_file=$2
    local output_dir=$3
    local settings_file=$4
    local dataset_name=$5  # We pass the dataset name so we can use it below
    local EVAL_RESULTS_FILE=$6

    echo "Running SLAM approaches on dataset $dataset_path..."

    ###############################
    # Approach 1: ORB-SLAM3 (rgbd_tum)
    ###############################
    echo "Starting ORB-SLAM3 (rgbd_tum) approach..." | tee -a "$EVAL_RESULTS_FILE"
    chmod +x ./Examples/RGB-D/rgbd_tum
    start_time=$(date +%s.%N)
    ./Examples/RGB-D/rgbd_tum \
        "$vocab_file" \
        "$settings_file" \
        "$dataset_path" \
        "Examples/RGB-D/associations/${dataset_name}.txt"
    end_time=$(date +%s.%N)
    runtime=$(echo "$end_time - $start_time" | bc)
    echo "Runtime for ORB-SLAM3 (rgbd_tum): $runtime seconds" | tee -a "$EVAL_RESULTS_FILE"

    # Evaluate approach 1
    GROUNDTRUTH_FILE="$dataset_path/groundtruth.txt"
    RESULTS_FILE="CameraTrajectory.txt"
    # Ensure we have a results file
    touch "$RESULTS_FILE"

    echo "======================" | tee -a "$EVAL_RESULTS_FILE"
    echo "Evaluation results for dataset: $dataset_name (ORB-SLAM3)" | tee -a "$EVAL_RESULTS_FILE"
    echo "----------------------" | tee -a "$EVAL_RESULTS_FILE"
    evaluate_results "$GROUNDTRUTH_FILE" "$RESULTS_FILE" "$EVAL_RESULTS_FILE"
    echo "======================" | tee -a "$EVAL_RESULTS_FILE"

    ###############################
    # Approach 2: PRIOR-SLAM (rgbd_prior_tum_vi)
    ###############################
    echo "Starting PRIOR-SLAM (rgbd_prior_tum_vi) approach..." | tee -a "$EVAL_RESULTS_FILE"
    start_time=$(date +%s.%N)
    ./PRIOR-SLAM/Examples/RGB-D/rgbd_prior_tum_vi \
        "$vocab_file" \
        "$settings_file" \
        "$dataset_path" \
        "Examples/RGB-D/associations/${dataset_name}.txt"
    end_time=$(date +%s.%N)
    runtime=$(echo "$end_time - $start_time" | bc)
    echo "Runtime for PRIOR-SLAM (rgbd_prior_tum_vi): $runtime seconds" | tee -a "$EVAL_RESULTS_FILE"

    # Evaluate approach 2
    GROUNDTRUTH_FILE="$dataset_path/groundtruth.txt"
    RESULTS_FILE="CameraTrajectory.txt"
    # Ensure we have a results file
    touch "$RESULTS_FILE"

    echo "======================" | tee -a "$EVAL_RESULTS_FILE"
    echo "Evaluation results for dataset: $dataset_name (PRIOR-SLAM)" | tee -a "$EVAL_RESULTS_FILE"
    echo "----------------------" | tee -a "$EVAL_RESULTS_FILE"
    evaluate_results "$GROUNDTRUTH_FILE" "$RESULTS_FILE" "$EVAL_RESULTS_FILE"
    echo "======================" | tee -a "$EVAL_RESULTS_FILE"
    
    echo "Finished processing dataset: $dataset_name"
}

###############################################################################
# Define dataset URLs and directories
# Make sure you have matching association files for each dataset in:
#   Examples/RGB-D/associations/<dataset_name>.txt
###############################################################################
declare -A datasets=(
    ["fr1_desk"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg1/rgbd_dataset_freiburg1_desk.tgz"
    ["fr1_desk2"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg1/rgbd_dataset_freiburg1_desk2.tgz"
    ["fr1_room"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg1/rgbd_dataset_freiburg1_room.tgz"
    ["fr1_xyz"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg1/rgbd_dataset_freiburg1_xyz.tgz"

    ["fr2_desk"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg2/rgbd_dataset_freiburg2_desk.tgz"

    ["fr3_nstr_tex_near"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/rgbd_dataset_freiburg3_nostructure_texture_near.tgz"
    ["fr3_office_val"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/rgbd_dataset_freiburg3_long_office_validation.tgz"
    ["fr3_office"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/rgbd_dataset_freiburg3_long_office_household.tgz"
    ["fr3_str_tex_far"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/rgbd_dataset_freiburg3_structure_texture_far.tgz"
    ["fr3_str_tex_near"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/rgbd_dataset_freiburg3_structure_texture_near.tgz"
)

VOCAB_FILE="Vocabulary/ORBvoc.txt"
OUTPUT_DIR="output"
SETTINGS_FILE="Examples/RGB-D/TUM1.yaml"
EVAL_RESULTS_FILE="slam_eval_results.txt"

# Clear the evaluation results file
> "$EVAL_RESULTS_FILE"

###############################################################################
# Main loop: Download, extract, run SLAM approaches, and evaluate
###############################################################################
for dataset_name in "${!datasets[@]}"; do
    DATASET_URL="${datasets[$dataset_name]}"
    DATASET_DIR="datasets/$dataset_name"

    # 1. Download if not present
    download_dataset "$DATASET_URL" "$dataset_name" "$DATASET_DIR"

    # 2. Extract the dataset
    if [ -f "$DATASET_DIR/$dataset_name.tgz" ]; then
        echo "Extracting $dataset_name..."
        tar -xzf "$DATASET_DIR/$dataset_name.tgz" -C "$DATASET_DIR" --strip-components=1
    fi

    # 3. Run both SLAM approaches and evaluate
    run_orbslam3 "$DATASET_DIR" "$VOCAB_FILE" "$OUTPUT_DIR" "$SETTINGS_FILE" "$dataset_name" "$EVAL_RESULTS_FILE"

    echo "--------------------------------------------------"
    echo "Done with dataset: $dataset_name"
    echo "--------------------------------------------------"
done

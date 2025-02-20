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
# Function to run ORB-SLAM3 on a dataset
###############################################################################
run_orbslam3() {
    local dataset_path=$1
    local vocab_file=$2
    local output_dir=$3
    local settings_file=$4
    local dataset_name=$5  # We pass the dataset name so we can use it below

    echo "Running ORB-SLAM3 on dataset $dataset_path..."
    chmod +x ./Examples/RGB-D/rgbd_tum
    ./Examples/RGB-D/rgbd_tum \
        "$vocab_file" \
        "$settings_file" \
        "$dataset_path" \
        "Examples/RGB-D/associations/${dataset_name}.txt"
    echo "ORB-SLAM3 finished processing the dataset."
}

###############################################################################
# Function to evaluate results
###############################################################################
evaluate_results() {
    local groundtruth_file=$1
    local results_file=$2

    echo "Evaluating results..."
    python3 ./evaluation/evaluate_ate_scale.py \
        "$groundtruth_file" \
        "$results_file"
    echo "Evaluation complete!"
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

###############################################################################
# Main loop: Download, extract, run ORB-SLAM3, and evaluate
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

    # 3. Run ORB-SLAM3
    run_orbslam3 "$DATASET_DIR" "$VOCAB_FILE" "$OUTPUT_DIR" "$SETTINGS_FILE" "$dataset_name"

    # 4. Evaluate
    GROUNDTRUTH_FILE="$DATASET_DIR/groundtruth.txt"
    RESULTS_FILE="CameraTrajectory.txt"
    # Ensure we have a results file
    touch "$RESULTS_FILE"

    evaluate_results "$GROUNDTRUTH_FILE" "$RESULTS_FILE"

    echo "--------------------------------------------------"
    echo "Done with dataset: $dataset_name"
    echo "--------------------------------------------------"
done

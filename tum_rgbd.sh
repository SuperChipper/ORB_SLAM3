#!/bin/bash

# Function to check if a dataset exists, and download it if not
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

# Function to run ORB-SLAM3 on a dataset
run_orbslam3() {
    local dataset_path=$1
    local vocab_file=$2
    local output_dir=$3
    local settings_file=$4

    echo "Running ORB-SLAM3 on dataset $dataset_path..."
    chmod +x ./Examples/RGB-D/rgbd_tum
    ./Examples/RGB-D/rgbd_tum \
        $vocab_file \
        $settings_file \
        $dataset_path \
        Examples/RGB-D/associations/$dataset_name.txt 
    echo "ORB-SLAM3 finished processing the dataset."
}

# Function to evaluate results
evaluate_results() {
    local groundtruth_file=$1
    local results_file=$2

    echo "Evaluating results..."
    python3 ./evaluation/evaluate_ate_scale.py \
        $groundtruth_file \
        $results_file
    echo "Evaluation complete!"
}

# Define dataset URLs and directories
declare -A datasets
datasets=(
    ["fr1_xyz"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg1/rgbd_dataset_freiburg1_xyz.tgz"
    #["fr1_rpy"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg1/rgbd_dataset_freiburg1_rpy.tgz"
    ["fr2_xyz"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg2/rgbd_dataset_freiburg2_xyz.tgz"
    #["fr2_rpy"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg2/rgbd_dataset_freiburg2_rpy.tgz"
    ["fr3_long_office_household"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/rgbd_dataset_freiburg3_long_office_household.tgz"
    ["fr3_nostructure_notexture_far"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/rgbd_dataset_freiburg3_nostructure_notexture_far.tgz"
    #["fr3_nostructure_notexture_near_withloop"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/rgbd_dataset_freiburg3_nostructure_notexture_near_withloop.tgz"
    ["fr3_nostructure_texture_far"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/rgbd_dataset_freiburg3_nostructure_texture_far.tgz"
    #["fr3_nostructure_texture_near_withloop"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/rgbd_dataset_freiburg3_nostructure_texture_near_withloop.tgz"
)

VOCAB_FILE="Vocabulary/ORBvoc.txt"
OUTPUT_DIR="output"
SETTINGS_FILE="Examples/RGB-D/TUM1.yaml"

# Loop through each dataset
for dataset_name in "${!datasets[@]}"; do
    DATASET_URL=${datasets[$dataset_name]}
    DATASET_DIR="datasets/$dataset_name"

    # Check and download dataset
    download_dataset $DATASET_URL $dataset_name $DATASET_DIR
    tar -xzf "$DATASET_DIR/$dataset_name.tgz" -C $DATASET_DIR --strip-components=1 # Extract the dataset

    # Run ORB-SLAM3
    run_orbslam3 $DATASET_DIR $VOCAB_FILE $OUTPUT_DIR $SETTINGS_FILE

    # Define groundtruth and result files for evaluation
    GROUNDTRUTH_FILE="$DATASET_DIR/groundtruth.txt"
    
    RESULTS_FILE="CameraTrajectory.txt"
    touch $RESULTS_FILE
    # Evaluate the results
    evaluate_results $GROUNDTRUTH_FILE $RESULTS_FILE
done



# 默认设置
DATASET_DIR="$HOME/Datasets/TUM_RGBD"  # 数据集保存目录
DATASET_TO_RUN="fr1/xyz"               # 默认运行fr1/xyz示例
RUN_ONLY=false                         # 是否只运行示例，不下载数据集
FORCE_DOWNLOAD=false                   # 强制下载，即使数据集目录已存在
ENABLE_VIEWER=true                     # 是否启用查看器
RUN_ALL=false                          # 是否运行所有数据集
RESULTS_DIR="runs"                     # 结果保存目录
EVAL_DIR="$RESULTS_DIR/evaluation"     # 评估结果保存目录
LOG_DIR="$RESULTS_DIR/logs"           # 日志目录
MAX_RETRIES=3                         # 最大重试次数

# 创建必要的目录
mkdir -p "$DATASET_DIR"
mkdir -p "$DATASET_DIR/associations"
mkdir -p "$RESULTS_DIR"
mkdir -p "$EVAL_DIR"
mkdir -p "$LOG_DIR"

# 日志函数
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_DIR/run.log"
}

# 错误处理函数
handle_error() {
    local dataset=$1
    local error_code=$2
    local error_message=$3
    log_message "ERROR" "处理数据集 $dataset 时发生错误: $error_message (错误码: $error_code)"
    return $error_code
}

# TUM RGB-D 数据集URL - 使用新的URL结构
declare -A DATASET_URLS=(
    ["fr1/xyz"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg1/rgbd_dataset_freiburg1_xyz.tgz"
    ["fr1/rpy"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg1/rgbd_dataset_freiburg1_rpy.tgz"
    ["fr1/360"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg1/rgbd_dataset_freiburg1_360.tgz"
    ["fr1/desk"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg1/rgbd_dataset_freiburg1_desk.tgz"
    ["fr2/xyz"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg2/rgbd_dataset_freiburg2_xyz.tgz"
    ["fr2/rpy"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg2/rgbd_dataset_freiburg2_rpy.tgz"
    ["fr2/desk"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg2/rgbd_dataset_freiburg2_desk.tgz"
    ["fr3/long_office"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/rgbd_dataset_freiburg3_long_office_household.tgz"
    ["fr3/nst"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/rgbd_dataset_freiburg3_nostructure_texture_near_withloop.tgz"
    ["fr3/nst_far"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/rgbd_dataset_freiburg3_nostructure_texture_far.tgz"
    ["fr3/sit_xyz"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/rgbd_dataset_freiburg3_sitting_xyz.tgz"
    ["fr3/sit_halfsph"]="https://cvg.cit.tum.de/rgbd/dataset/freiburg3/rgbd_dataset_freiburg3_sitting_halfsphere.tgz"
)

# 根据数据集名称获取有效的文件夹名称
get_folder_name() {
    local dataset=$1
    local folder_name

    # 将数据集名称转换为文件夹名称
    case $dataset in
        "fr1/xyz") folder_name="rgbd_dataset_freiburg1_xyz" ;;
        "fr1/rpy") folder_name="rgbd_dataset_freiburg1_rpy" ;;
        "fr1/360") folder_name="rgbd_dataset_freiburg1_360" ;;
        "fr1/desk") folder_name="rgbd_dataset_freiburg1_desk" ;;
        "fr2/xyz") folder_name="rgbd_dataset_freiburg2_xyz" ;;
        "fr2/rpy") folder_name="rgbd_dataset_freiburg2_rpy" ;;
        "fr2/desk") folder_name="rgbd_dataset_freiburg2_desk" ;;
        "fr3/long_office") folder_name="rgbd_dataset_freiburg3_long_office_household" ;;
        "fr3/nst") folder_name="rgbd_dataset_freiburg3_nostructure_texture_near_withloop" ;;
        "fr3/nst_far") folder_name="rgbd_dataset_freiburg3_nostructure_texture_far" ;;
        "fr3/sit_xyz") folder_name="rgbd_dataset_freiburg3_sitting_xyz" ;;
        "fr3/sit_halfsph") folder_name="rgbd_dataset_freiburg3_sitting_halfsphere" ;;
        *) folder_name="" ;;
    esac

    echo "$folder_name"
}

# 获取关联文件名
get_association_filename() {
    local dataset=$1
    local folder_name=$(get_folder_name "$dataset")
    
    if [ -n "$folder_name" ]; then
        echo "${folder_name}-associations.txt"
    else
        echo ""
    fi
}

# 生成关联文件函数
generate_associations() {
    local dataset_folder=$1
    local output_file=$2
    
    echo "生成关联文件: $output_file"
    
    # 确保python命令可用
    if ! command -v python3 &> /dev/null; then
        echo "错误: 需要Python来生成关联文件"
        return 1
    fi
    
    # 创建一个临时Python脚本来生成关联文件
    local temp_script=$(mktemp)
    cat > "$temp_script" <<EOF
#!/usr/bin/env python3
import os
import sys
import glob
import re
import numpy as np

def read_file_list(filename):
    file_list = []
    with open(filename, 'r') as f:
        for line in f:
            if line.strip() and not line.startswith('#'):
                data = line.split()
                file_list.append((float(data[0]), data[1]))
    return file_list

def generate_associations(rgb_list, depth_list, max_diff=0.02):
    associations = []
    for i, (rgb_time, rgb_file) in enumerate(rgb_list):
        best_depth = None
        best_diff = float('inf')
        for j, (depth_time, depth_file) in enumerate(depth_list):
            diff = abs(rgb_time - depth_time)
            if diff < best_diff:
                best_diff = diff
                best_depth = (depth_time, depth_file)
                
        if best_depth and best_diff < max_diff:
            associations.append((rgb_time, rgb_file, best_depth[0], best_depth[1]))
    return associations

def main():
    if len(sys.argv) != 3:
        print("Usage: python script.py <dataset_folder> <output_file>")
        return
        
    dataset_folder = sys.argv[1]
    output_file = sys.argv[2]
    
    rgb_list_file = os.path.join(dataset_folder, 'rgb.txt')
    depth_list_file = os.path.join(dataset_folder, 'depth.txt')
    
    if not os.path.exists(rgb_list_file) or not os.path.exists(depth_list_file):
        print("Error: rgb.txt or depth.txt not found")
        return
        
    rgb_list = read_file_list(rgb_list_file)
    depth_list = read_file_list(depth_list_file)
    
    associations = generate_associations(rgb_list, depth_list)
    
    with open(output_file, 'w') as f:
        for rgb_time, rgb_file, depth_time, depth_file in associations:
            f.write(f"{rgb_time:.6f} {rgb_file} {depth_time:.6f} {depth_file}\n")
            
    print(f"Generated association file with {len(associations)} entries")

if __name__ == "__main__":
    main()
EOF

    # 执行Python脚本
    python3 "$temp_script" "$dataset_folder" "$output_file"
    result=$?
    
    # 删除临时脚本
    rm "$temp_script"
    
    # 检查文件是否生成成功
    if [ $result -eq 0 ] && [ -f "$output_file" ]; then
        echo "关联文件生成成功，共 $(wc -l < "$output_file") 个条目"
        return 0
    else
        echo "关联文件生成失败"
        return 1
    fi
}

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -o, --output-dir DIR     指定数据集输出目录 (默认: $DATASET_DIR)"
    echo "  -d, --dataset NAME       指定要运行的数据集 (默认: $DATASET_TO_RUN)"
    echo "                           可选值: fr1/xyz, fr1/rpy, fr1/360, fr1/desk,"
    echo "                                  fr2/xyz, fr2/rpy, fr2/desk,"
    echo "                                  fr3/long_office, fr3/nst, fr3/nst_far,"
    echo "                                  fr3/sit_xyz, fr3/sit_halfsph"
    echo "  -a, --all                运行所有可用的数据集"
    echo "  -r, --run-only           只运行示例，不下载数据集"
    echo "  -f, --force-download     强制下载，即使数据集目录已存在 (默认: 不强制)"
    echo "  -n, --no-viewer          禁用3D查看器"
    echo "  -h, --help               显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                        # 下载数据集并运行fr1/xyz示例"
    echo "  $0 -d fr2/desk            # 下载数据集并运行fr2/desk示例"
    echo "  $0 -a                     # 运行所有可用的数据集"
    echo "  $0 -r -d fr1/rpy          # 仅运行fr1/rpy示例（假设数据集已存在）"
    echo "  $0 -f -d fr3/long_office  # 强制重新下载fr3/long_office数据集并运行"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output-dir)
            DATASET_DIR="$2"
            shift 2
            ;;
        -d|--dataset)
            DATASET_TO_RUN="$2"
            shift 2
            ;;
        -a|--all)
            RUN_ALL=true
            shift
            ;;
        -r|--run-only)
            RUN_ONLY=true
            shift
            ;;
        -f|--force-download)
            FORCE_DOWNLOAD=true
            shift
            ;;
        -n|--no-viewer)
            ENABLE_VIEWER=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 运行单个数据集的函数
run_single_dataset() {
    local dataset=$1
    local retry_count=0
    local success=false
    
    log_message "INFO" "==============================================="
    log_message "INFO" "开始处理数据集: $dataset"
    log_message "INFO" "==============================================="
    
    while [ $retry_count -lt $MAX_RETRIES ] && [ "$success" = false ]; do
        if [ $retry_count -gt 0 ]; then
            log_message "INFO" "重试处理数据集 $dataset (第 $retry_count 次)"
        fi
        
        # 获取数据集文件夹名
        local dataset_folder=$(get_folder_name "$dataset")
        if [ -z "$dataset_folder" ]; then
            handle_error "$dataset" 1 "无法确定数据集文件夹名: $dataset"
            return 1
        fi
        
        # 获取关联文件名
        local association_file=$(get_association_filename "$dataset")
        if [ -z "$association_file" ]; then
            handle_error "$dataset" 1 "无法确定关联文件名: $dataset"
            return 1
        fi
        
        # 确定配置文件
        local config_file
        if [[ "$dataset" == fr1/* ]]; then
            config_file="TUM1.yaml"
        elif [[ "$dataset" == fr2/* ]]; then
            config_file="TUM2.yaml"
        elif [[ "$dataset" == fr3/* ]]; then
            config_file="TUM3.yaml"
        else
            handle_error "$dataset" 1 "无法确定配置文件: $dataset"
            return 1
        fi
        
        # 检查必要的文件和目录
        if [ ! -f "./Examples/RGB-D/rgbd_tum" ]; then
            handle_error "$dataset" 1 "未找到rgbd_tum可执行文件，请先编译ORB-SLAM3"
            return 1
        fi
        
        if [ ! -f "./Vocabulary/ORBvoc.txt" ]; then
            handle_error "$dataset" 1 "未找到ORBvoc.txt词汇文件，请确保已经解压词汇文件"
            return 1
        fi
        
        if [ ! -f "./Examples/RGB-D/$config_file" ]; then
            handle_error "$dataset" 1 "未找到配置文件: $config_file"
            return 1
        fi
        
        # 下载数据集（如果需要）
        if [ "$RUN_ONLY" = false ]; then
            if [ -d "$DATASET_DIR/$dataset_folder" ] && [ "$(ls -A "$DATASET_DIR/$dataset_folder" 2>/dev/null)" ] && [ "$FORCE_DOWNLOAD" = false ]; then
                log_message "INFO" "数据集 $dataset 已存在，跳过下载"
            else
                log_message "INFO" "下载数据集: $dataset"
                cd "$DATASET_DIR" || return 1
                wget -c "${DATASET_URLS[$dataset]}" -O "$dataset_folder.tgz"
                tar -xzf "$dataset_folder.tgz"
                cd - || return 1
            fi
        fi
        
        # 生成关联文件
        if [ ! -f "$DATASET_DIR/associations/$association_file" ] || [ "$FORCE_DOWNLOAD" = true ]; then
            log_message "INFO" "生成关联文件: $association_file"
            generate_associations "$DATASET_DIR/$dataset_folder" "$DATASET_DIR/associations/$association_file"
        fi
        
        # 构建运行命令
        local viewer_flag=""
        if [ "$ENABLE_VIEWER" = false ]; then
            viewer_flag="--quiet"
        fi
        
        # 运行RGB-D示例
        log_message "INFO" "运行ORB-SLAM3 RGB-D示例: $dataset"
        ./Examples/RGB-D/rgbd_tum ./Vocabulary/ORBvoc.txt "./Examples/RGB-D/$config_file" "$DATASET_DIR/$dataset_folder" "$DATASET_DIR/associations/$association_file" $viewer_flag
        
        local run_status=$?
        # if [ $run_status -ne 0 ]; then
        #     log_message "ERROR" "ORB-SLAM3运行失败，错误码: $run_status"
        #     retry_count=$((retry_count + 1))
        #     if [ $retry_count -lt $MAX_RETRIES ]; then
        #         log_message "INFO" "等待5秒后重试..."
        #         sleep 5
        #         continue
        #     else
        #         handle_error "$dataset" $run_status "达到最大重试次数，放弃处理数据集"
        #         return $run_status
        #     fi
        # fi
        
        # 保存结果
        local dataset_prefix=$(echo "$dataset" | tr '/' '_')
        
        # 确保结果目录存在
        mkdir -p "$RESULTS_DIR"
        mkdir -p "$EVAL_DIR"
        
        # 移动结果文件
        if [ -f "result.pcd" ]; then
            mv "result.pcd" "$RESULTS_DIR/${dataset_prefix}.pcd"
            log_message "INFO" "已保存点云结果到: $RESULTS_DIR/${dataset_prefix}.pcd"
        fi
        
        if [ -f "CameraTrajectory.txt" ]; then
            mv "CameraTrajectory.txt" "$RESULTS_DIR/${dataset_prefix}_camera_trajectory.txt"
            log_message "INFO" "已保存相机轨迹到: $RESULTS_DIR/${dataset_prefix}_camera_trajectory.txt"
        fi
        
        if [ -f "KeyFrameTrajectory.txt" ]; then
            mv "KeyFrameTrajectory.txt" "$RESULTS_DIR/${dataset_prefix}_keyframe_trajectory.txt"
            log_message "INFO" "已保存关键帧轨迹到: $RESULTS_DIR/${dataset_prefix}_keyframe_trajectory.txt"
        fi
        
        # 评估结果
        local gt_file="$DATASET_DIR/$dataset_folder/groundtruth.txt"
        if [ -f "./evaluation/evaluate_ate_scale.py" ] && [ -f "$gt_file" ]; then
            log_message "INFO" "评估轨迹准确性: $dataset"
            python3 ./evaluation/evaluate_ate_scale.py "$gt_file" "$RESULTS_DIR/${dataset_prefix}_camera_trajectory.txt" \
                --verbose \
                --plot "$EVAL_DIR/${dataset_prefix}_trajectory.pdf" \
                --save "$EVAL_DIR/${dataset_prefix}_ate_results.txt"
            
            if [ $? -eq 0 ]; then
                log_message "INFO" "轨迹评估完成，结果保存在: $EVAL_DIR/${dataset_prefix}_trajectory.pdf"
                log_message "INFO" "评估数据保存在: $EVAL_DIR/${dataset_prefix}_ate_results.txt"
            else
                log_message "ERROR" "轨迹评估失败"
            fi
        fi
        
        success=true
    done
    
    log_message "INFO" "数据集 $dataset 处理完成"
    log_message "INFO" "==============================================="
    return 0
}

# 主程序
if [ "$RUN_ALL" = true ]; then
    log_message "INFO" "将运行所有可用的数据集"
    local failed_datasets=()
    
    for dataset in "${!DATASET_URLS[@]}"; do
        if ! run_single_dataset "$dataset"; then
            failed_datasets+=("$dataset")
        fi
    done
    
    if [ ${#failed_datasets[@]} -eq 0 ]; then
        log_message "INFO" "所有数据集处理完成"
    else
        log_message "WARNING" "以下数据集处理失败: ${failed_datasets[*]}"
        log_message "INFO" "其他数据集处理完成"
    fi
else
    # 验证选择的数据集
    if [ -z "${DATASET_URLS[$DATASET_TO_RUN]}" ]; then
        handle_error "$DATASET_TO_RUN" 1 "无效的数据集名称"
        exit 1
    fi
    
    run_single_dataset "$DATASET_TO_RUN"
fi

log_message "INFO" "脚本执行完毕" 
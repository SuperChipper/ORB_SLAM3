#!/bin/bash

# 默认设置
DATASET_DIR="$HOME/Datasets/EuRoC"  # 数据集保存目录
DATASET_TO_RUN="MH01"  # 默认运行Machine Hall 01示例
RUN_ONLY=false  # 是否只运行示例，不下载数据集
FORCE_DOWNLOAD=false  # 强制下载，即使数据集目录已存在

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -o, --output-dir DIR     指定数据集输出目录 (默认: $DATASET_DIR)"
    echo "  -d, --dataset NAME       指定要运行的数据集 (默认: $DATASET_TO_RUN)"
    echo "                           可选值: MH01, MH02, MH03, MH04, MH05, V101, V102, V103, V201, V202, V203"
    echo "  -r, --run-only           只运行示例，不下载数据集"
    echo "  -f, --force-download     强制下载，即使数据集目录已存在 (默认: 不强制)"
    echo "  -h, --help               显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                        # 下载数据集并运行MH01示例"
    echo "  $0 -d MH03                # 下载数据集并运行MH03示例"
    echo "  $0 -r -d MH02             # 仅运行MH02示例（假设数据集已存在）"
    echo "  $0 -f -d MH04             # 强制重新下载MH04数据集并运行"
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
        -r|--run-only)
            RUN_ONLY=true
            shift
            ;;
        -f|--force-download)
            FORCE_DOWNLOAD=true
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

# 验证选择的数据集
valid_datasets=("MH01" "MH02" "MH03" "MH04" "MH05" "V101" "V102" "V103" "V201" "V202" "V203")
valid=false
for ds in "${valid_datasets[@]}"; do
    if [ "$ds" = "$DATASET_TO_RUN" ]; then
        valid=true
        break
    fi
done

if [ "$valid" = false ]; then
    echo "错误: 无效的数据集名称: $DATASET_TO_RUN"
    echo "有效的数据集名称: ${valid_datasets[*]}"
    exit 1
fi

# 检查是否已经编译过ORB-SLAM3
if [ ! -f "./Examples/Stereo/stereo_euroc" ]; then
    echo "错误: 未找到stereo_euroc可执行文件"
    echo "请先编译ORB-SLAM3"
    echo "运行: ./build.sh"
    exit 1
fi

# 检查词汇文件是否存在
if [ ! -f "./Vocabulary/ORBvoc.txt" ]; then
    echo "错误: 未找到ORBvoc.txt词汇文件"
    echo "请确保已经解压词汇文件"
    exit 1
fi

# 检查配置文件是否存在
if [ ! -f "./Examples/Stereo/EuRoC.yaml" ]; then
    echo "错误: 未找到EuRoC.yaml配置文件"
    exit 1
fi

# 检查是否存在时间戳文件
if [ ! -f "./Examples/Stereo/EuRoC_TimeStamps/${DATASET_TO_RUN}.txt" ]; then
    echo "错误: 未找到${DATASET_TO_RUN}.txt时间戳文件"
    exit 1
fi

# 下载数据集
if [ "$RUN_ONLY" = false ]; then
    # 检查数据集是否已存在
    if [ -d "$DATASET_DIR/$DATASET_TO_RUN" ] && [ "$(ls -A "$DATASET_DIR/$DATASET_TO_RUN" 2>/dev/null)" ] && [ "$FORCE_DOWNLOAD" = false ]; then
        echo "数据集 $DATASET_TO_RUN 已存在于 $DATASET_DIR/$DATASET_TO_RUN"
        echo "将跳过下载步骤"
        
        # 询问用户是否仍要下载
        echo "是否仍要下载数据集？ (y/n) [n]"
        read -r answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            echo "用户选择重新下载数据集"
        else
            echo "跳过数据集下载"
            # 设置为只运行模式
            RUN_ONLY=true
        fi
    else
        if [ "$FORCE_DOWNLOAD" = true ]; then
            echo "强制重新下载数据集 $DATASET_TO_RUN"
        else
            echo "数据集 $DATASET_TO_RUN 不存在，将进行下载"
        fi
    fi
fi

# 如果需要下载数据集
if [ "$RUN_ONLY" = false ]; then
    echo "准备下载数据集: $DATASET_TO_RUN"
    
    # 检查download_euroc_stereo_simple.sh是否存在
    if [ ! -f "./download_euroc_stereo_simple.sh" ]; then
        echo "错误: 未找到download_euroc_stereo_simple.sh脚本"
        echo "您可以手动下载脚本或数据集"
        exit 1
    fi
    
    # 给下载脚本添加执行权限
    chmod +x ./download_euroc_stereo_simple.sh
    
    # 执行下载脚本，仅下载需要的数据集
    if [ "$FORCE_DOWNLOAD" = true ]; then
        ./download_euroc_stereo_simple.sh -o "$DATASET_DIR" -n -f
    else
        ./download_euroc_stereo_simple.sh -o "$DATASET_DIR" -n
    fi
    
    # 检查数据集是否下载成功
    if [ ! -d "$DATASET_DIR/$DATASET_TO_RUN" ]; then
        echo "错误: 数据集下载失败或不完整: $DATASET_TO_RUN"
        echo "请检查下载路径或手动下载数据集"
        exit 1
    fi
else
    echo "跳过数据集下载，直接运行示例"
    
    # 检查数据集是否存在
    if [ ! -d "$DATASET_DIR/$DATASET_TO_RUN" ]; then
        echo "错误: 数据集不存在: $DATASET_DIR/$DATASET_TO_RUN"
        echo "请使用-o参数指定正确的数据集目录，或移除-r参数下载数据集"
        exit 1
    fi
fi

# 运行立体视觉示例
echo "正在运行ORB-SLAM3立体视觉示例: $DATASET_TO_RUN"
./Examples/Stereo/stereo_euroc ./Vocabulary/ORBvoc.txt ./Examples/Stereo/EuRoC.yaml "$DATASET_DIR/$DATASET_TO_RUN" ${DATASET_DIR}/EuRoC_TimeStamps/${DATASET_TO_RUN}.txt dataset-${DATASET_TO_RUN}_stereo

# 检查运行结果
if [ $? -ne 0 ]; then
    echo "示例运行失败"
    exit 1
else
    echo "示例运行成功完成!"
    echo "结果保存在: f_dataset-${DATASET_TO_RUN}_stereo.txt"
fi

# 如果是评估版本，运行评估脚本
if [ -f "./evaluation/evaluate_ate_scale.py" ] && [ -f "./evaluation/Ground_truth/EuRoC_left_cam/${DATASET_TO_RUN}_GT.txt" ]; then
    echo "正在评估轨迹准确性..."
    python evaluation/evaluate_ate_scale.py evaluation/Ground_truth/EuRoC_left_cam/${DATASET_TO_RUN}_GT.txt f_dataset-${DATASET_TO_RUN}_stereo.txt --plot ${DATASET_TO_RUN}_stereo.pdf
    
    if [ $? -eq 0 ]; then
        echo "轨迹评估完成，结果保存在: ${DATASET_TO_RUN}_stereo.pdf"
    else
        echo "轨迹评估失败"
    fi
fi 
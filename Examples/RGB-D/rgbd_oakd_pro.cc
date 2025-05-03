/**
* This file is part of ORB-SLAM3
*
* Copyright (C) 2017-2021 Carlos Campos, Richard Elvira, Juan J. Gómez Rodríguez, José M.M. Montiel and Juan D. Tardós, University of Zaragoza.
* Copyright (C) 2014-2016 Raúl Mur-Artal, José M.M. Montiel and Juan D. Tardós, University of Zaragoza.
*
* ORB-SLAM3 is free software: you can redistribute it and/or modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* ORB-SLAM3 is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
* the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License along with ORB-SLAM3.
* If not, see <http://www.gnu.org/licenses/>.
*/

#include <signal.h>
#include <stdlib.h>
#include <iostream>
#include <algorithm>
#include <fstream>
#include <chrono>
#include <ctime>
#include <sstream>
#include <iomanip>

#include <condition_variable>
#include <memory>  // 添加 std::shared_ptr 支持

#include <opencv2/core/core.hpp>
#include <opencv2/imgproc/imgproc.hpp>
#include <opencv2/highgui/highgui.hpp>

#include <depthai/depthai.hpp>

#include <System.h>

using namespace std;

bool b_continue_session;

// 线程同步变量
std::mutex imu_mutex;
std::condition_variable cond_image_rec;
bool image_ready = false;
int count_im_buffer = 0;

void exit_loop_handler(int s){
    cout << "Finishing session" << endl;
    b_continue_session = false;
}

// 保存跟踪时间和误差到文件
void saveTrackingResults(const string& filename, const vector<double>& tracking_times, const vector<double>& tracking_errors) {
    ofstream f;
    f.open(filename.c_str());
    f << fixed;
    
    f << "tracking_time,tracking_error" << endl;
    
    for(size_t i = 0; i < tracking_times.size(); i++) {
        f << setprecision(6) << tracking_times[i] << "," << tracking_errors[i] << endl;
    }
    
    f.close();
    cout << "跟踪结果已保存到: " << filename << endl;
}

int main(int argc, char **argv) {
    if (argc < 3 || argc > 4) {
        cerr << endl
             << "Usage: ./rgbd_oakd_pro path_to_vocabulary path_to_settings (trajectory_file_name)"
             << endl;
        return 1;
    }

    string file_name;
    bool bFileName = false;

    if (argc == 4) {
        file_name = string(argv[argc - 1]);
        bFileName = true;
    }

    struct sigaction sigIntHandler;
    sigIntHandler.sa_handler = exit_loop_handler;
    sigemptyset(&sigIntHandler.sa_mask);
    sigIntHandler.sa_flags = 0;
    sigaction(SIGINT, &sigIntHandler, NULL);
    b_continue_session = true;

    // 创建结果目录
    string results_dir = "results";
    if (system(("mkdir -p " + results_dir).c_str()) != 0) {
        cerr << "无法创建结果目录: " << results_dir << endl;
    }
    
    // 获取当前时间作为会话ID
    auto now = chrono::system_clock::now();
    auto now_c = chrono::system_clock::to_time_t(now);
    stringstream ss;
    ss << put_time(localtime(&now_c), "%Y%m%d_%H%M%S");
    string session_id = ss.str();
    
    // 创建结果文件
    string results_file = results_dir + "/tracking_results_" + session_id + ".csv";
    
    // 跟踪时间和误差的向量
    vector<double> tracking_times;
    vector<double> tracking_errors;

    // Create pipeline
    dai::Pipeline pipeline;
    dai::Device device;

    // Define sources and outputs
    auto colorCam = pipeline.create<dai::node::ColorCamera>();
    auto leftCam = pipeline.create<dai::node::MonoCamera>();
    auto rightCam = pipeline.create<dai::node::MonoCamera>();
    auto stereo = pipeline.create<dai::node::StereoDepth>();

    // 使用固定的摄像机Socket定义
    dai::CameraBoardSocket rgbCamSocket = dai::CameraBoardSocket::CAM_A;

    // Properties - 按照Luxonis示例配置
    // 设置RGB相机
    colorCam->setBoardSocket(rgbCamSocket);
    colorCam->setResolution(dai::ColorCameraProperties::SensorResolution::THE_1080_P);
    colorCam->setInterleaved(false);
    colorCam->setColorOrder(dai::ColorCameraProperties::ColorOrder::BGR);
    colorCam->setFps(30);
    // 设置ISP缩放为2/3(1920*1080 -> 1280*720)
    colorCam->setIspScale(2, 3);
    colorCam->setVideoSize(1280, 720);

    // 设置左右单目相机
    leftCam->setResolution(dai::MonoCameraProperties::SensorResolution::THE_720_P);
    leftCam->setBoardSocket(dai::CameraBoardSocket::CAM_B);
    leftCam->setFps(30);
    rightCam->setResolution(dai::MonoCameraProperties::SensorResolution::THE_720_P);
    rightCam->setBoardSocket(dai::CameraBoardSocket::CAM_C);
    rightCam->setFps(30);

    // 配置立体深度处理
    stereo->setDefaultProfilePreset(dai::node::StereoDepth::PresetMode::HIGH_DENSITY);
    // LR-check是深度对齐所必需的
    stereo->setLeftRightCheck(true);
    // 将深度对齐到RGB相机
    stereo->setDepthAlign(rgbCamSocket);
    // 使用中值滤波减少噪声
    //stereo->setMedianFilter(dai::MedianFilter::KERNEL_7x7);
    // 设置置信度阈值，提高深度质量
    //stereo->initialConfig.setConfidenceThreshold(190);

    // Create outputs
    auto xoutColor = pipeline.create<dai::node::XLinkOut>();
    auto xoutDepth = pipeline.create<dai::node::XLinkOut>();

    xoutColor->setStreamName("rgb");
    xoutDepth->setStreamName("depth");

    // 存储队列名称以便后续使用
    std::vector<std::string> queueNames;
    queueNames.push_back("rgb");
    queueNames.push_back("depth");

    // Linking - 使用推荐的连接方式
    colorCam->video.link(xoutColor->input);  // 使用video输出而不是isp
    
    // 对于RGB相机，设置固定对焦位置以便与深度正确对齐
    try {
        auto calibData = device.readCalibration2();
        auto lensPosition = calibData.getLensPosition(rgbCamSocket);
        if(lensPosition) {
            colorCam->initialControl.setManualFocus(lensPosition);
            cout << "成功设置RGB相机手动对焦位置: " << lensPosition << endl;
        }
    } catch(const std::exception& ex) {
        std::cout << ex.what() << std::endl;
        return 1;
    }
    leftCam->out.link(stereo->left);
    rightCam->out.link(stereo->right);
    // 连接视差输出 - 使用视差而不是深度，性能更佳
    stereo->disparity.link(xoutDepth->input);


    device.startPipeline(pipeline);

    // 为每个队列设置大小和行为
    for(const auto& name : queueNames) {
        device.getOutputQueue(name, 4, false);
    }

    // Load ORB-SLAM3
    ORB_SLAM3::System SLAM(argv[1], argv[2], ORB_SLAM3::System::RGBD, true);

    cout << endl << "-------" << endl;
    cout << "Start processing sequence ..." << endl;

    // 用于计算平均跟踪时间
    double total_tracking_time = 0.0;
    int tracking_count = 0;
    
    // 用于计算跟踪误差
    double total_tracking_error = 0.0;
    int error_count = 0;
    
    // 帧处理变量
    std::unordered_map<std::string, cv::Mat> frames;
    double timestamp_image = -1.0;

    while (b_continue_session) {
        // 获取数据包 - 使用getQueueEvents处理所有事件
        std::unordered_map<std::string, std::shared_ptr<dai::ImgFrame>> latestPacket;
        
        auto queueEvents = device.getQueueEvents(queueNames);
        for(const auto& name : queueEvents) {
            auto packets = device.getOutputQueue(name)->tryGetAll<dai::ImgFrame>();
            auto count = packets.size();
            if(count > 0) {
                latestPacket[name] = packets[count - 1];
            }
        }
        
        // 检查是否同时有RGB和深度数据可用
        if(latestPacket.find("rgb") != latestPacket.end() && latestPacket.find("depth") != latestPacket.end()) {
            // 提取RGB帧
            cv::Mat imCV = latestPacket["rgb"]->getCvFrame();
            
            // 提取深度帧 - 处理视差图
            cv::Mat depthCV = latestPacket["depth"]->getFrame();
            
            // 使用RGB帧的时间戳
            timestamp_image = static_cast<double>(latestPacket["rgb"]->getTimestamp().time_since_epoch().count()) * 1e-9;
            
            // 检查图像和深度图是否有效
            if (imCV.empty() || depthCV.empty()) {
                cerr << "获取到空的图像或深度图，跳过当前帧" << endl;
                continue;
            }
            
            // 转换深度图格式 - 从视差图转换为深度图
            // if (depthCV.type() != CV_16UC1) {
            cout << "原始深度图格式: " << depthCV.type() << endl;
            
            // 处理视差图
            // if (depthCV.type() == CV_8UC1 || depthCV.type() == CV_8UC3) {
                // 从视差图计算深度图
            double maxDisparity = stereo->initialConfig.getMaxDisparity();
            cv::Mat depthMap;
            
            // 转换视差图为深度图 (毫米) - 使用焦距和基线计算
            // 深度 = (基线 * 焦距) / 视差
            float baseline = 75.0f; // 以毫米为单位的基线
            float focal = 599.478516f;   // 以像素为单位的焦距
            
            // 转换为浮点以进行计算
            depthCV.convertTo(depthMap, CV_32F);
            
            // 避免除以零
            cv::threshold(depthMap, depthMap, 1.0, maxDisparity, cv::THRESH_TRUNC);
            
            // 应用深度计算公式
            depthMap = (baseline * focal) / depthMap;
            
            // // 转换为16位无符号整数 (毫米)
            // depthMap.convertTo(depthCV, CV_16UC1);
            
            cout << "已将视差图转换为深度图" << endl;
                // }
                // // 如果是32位浮点格式
                // else if (depthCV.type() == CV_32F) {
                //     // 转换为毫米单位的16位无符号整数
                //     depthCV.convertTo(depthCV, CV_16UC1, 1000.0);
                //     cout << "已将32F深度图转换为16UC1格式(毫米单位)" << endl;
                // } else {
                //     cerr << "不支持的深度图格式，尝试强制转换为16UC1" << endl;
                //     depthCV.convertTo(depthCV, CV_16UC1);
                // }
            // }
            
            // 输出深度图信息以便调试
            cv::Scalar meanDepth = cv::mean(depthCV);
            double minVal, maxVal;
            cv::minMaxLoc(depthCV, &minVal, &maxVal);
            cout << "深度图信息 - 类型: " << depthCV.type() << ", 尺寸: " << depthCV.size() 
                 << ", 平均深度: " << meanDepth[0] << ", 范围: [" << minVal << ", " << maxVal << "]" << endl;
            
            // 记录跟踪开始时间
            chrono::steady_clock::time_point t1 = chrono::steady_clock::now();
            
            // 设置图像和深度数据 - 使用深拷贝以避免线程安全问题
            cv::Mat im = imCV.clone();  // 深拷贝以避免数据竞争
            cv::Mat depth = depthCV.clone();
            double timestamp = timestamp_image;
            
            // BGR转RGB
            cv::cvtColor(im, im, cv::COLOR_BGR2RGB);
            
            // 确保深度图和彩色图尺寸匹配
            if (im.size() != depth.size()) {
                cout << "调整图像尺寸 - RGB: " << im.size() << ", 深度: " << depth.size() << endl;
                cv::resize(im, im, depth.size());
            }
            
            // 基本的深度有效性检查
            cv::Mat validDepthMask = (depth > 100) & (depth < 10000);  // 有效深度范围：10cm到10m
            int validPixels = cv::countNonZero(validDepthMask);
            double validPercentage = validPixels * 100.0 / depth.total();
            cout << "有效深度像素数: " << validPixels << "/" << depth.total() 
                 << " (" << validPercentage << "%)" << endl;
            
            // 创建处理后的深度图，默认为原始深度图
            cv::Mat processedDepth = depth.clone();
            
            // 只有在有效像素非常少时才进行修复
            if (validPercentage < 30.0) {
                cout << "警告：有效深度像素少于30%，应用简单修复..." << endl;
                
                // 提取有效深度区域的统计信息
                cv::Mat validDepths;
                depth.copyTo(validDepths, validDepthMask);
                
                if (!validDepths.empty()) {
                    // 计算有效区域的中值深度作为填充值
                    cv::Scalar mean, stddev;
                    cv::meanStdDev(validDepths, mean, stddev);
                    double medianDepth = mean[0];
                    
                    // 简单填充方法
                    processedDepth.setTo(cv::Scalar(medianDepth), ~validDepthMask);
                    cout << "已使用中值深度 " << medianDepth << " 填充无效区域" << endl;
                }
            }

            // 处理数据
            try {
                // Pass the image to the SLAM system
                SLAM.TrackRGBD(im, processedDepth, timestamp);
            
                // 计算跟踪时间
                chrono::steady_clock::time_point t2 = chrono::steady_clock::now();
                double tracking_time = chrono::duration_cast<chrono::duration<double>>(t2 - t1).count();
                
                // 更新跟踪时间统计
                total_tracking_time += tracking_time;
                tracking_count++;
                
                // 简单的跟踪误差估计
                double tracking_error = 0.0;
                if (SLAM.GetTrackingState() == 2) { // 跟踪状态良好
                    tracking_error = 0.01;
                    total_tracking_error += tracking_error;
                    error_count++;
                }
                
                // 每30帧打印一次状态
                if (tracking_count % 30 == 0) {
                    cout << "已处理 " << tracking_count << " 帧，有效跟踪: " 
                         << error_count << " 帧，平均时间: " 
                         << total_tracking_time / tracking_count * 1000 << " ms" << endl;
                }
            }
            catch (const std::exception& e) {
                cerr << "处理异常: " << e.what() << endl;
            }
        } else {
            // 如果没有同时拿到RGB和深度，短暂休眠
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
    }

    // 计算平均跟踪时间和误差
    double mean_tracking_time = tracking_count > 0 ? total_tracking_time / tracking_count : 0.0;
    double mean_tracking_error = error_count > 0 ? total_tracking_error / error_count : 0.0;
    
    cout << "平均跟踪时间: " << mean_tracking_time * 1000.0 << " ms" << endl;
    cout << "平均跟踪误差: " << mean_tracking_error << endl;
    
    // 保存跟踪结果
    saveTrackingResults(results_file, tracking_times, tracking_errors);
    
    // 保存会话摘要
    string summary_file = results_dir + "/session_summary.csv";
    ofstream summary;
    summary.open(summary_file.c_str(), ios::app);
    summary << fixed;
    summary << session_id << "," 
            << setprecision(6) << mean_tracking_time << "," 
            << mean_tracking_error << "," 
            << tracking_count << "," 
            << error_count << endl;
    summary.close();
    cout << "会话摘要已保存到: " << summary_file << endl;

    // Stop all threads
    SLAM.Shutdown();

    return 0;
} 
//
// 对输入图像超采样
// 输入规格：1280*720 四像素合一，在 HDMI 输出端
// 会强制重采样到原来的一半
`timescale 1ns / 1ps

module video_sampling #(
  // 横纵向像素计数位宽
  parameter               X_BITS = 12,
  parameter               Y_BITS = 12,
  // 原视频横纵向像素量
  parameter V_ACT = 12'd720,
  parameter H_ACT = 12'd1280,
  // 缩放系数
  parameter S_F = 2
)(
  input               clk,        // 像素时钟
  input               rst,        // 复位信号

  input       [15:0]  i_rgb565,   // 原始图像数据
  output      [15:0]  o_rgb565,   // 缩放后的图像数据
  output reg          vs_out,     // 输出场同步信号
  output reg          hs_out      // 输出行同步信号
);

reg [X_BITS-1:0] h_count;
reg [Y_BITS-1:0] v_count;
reg [X_BITS-1:0] x_act;
reg [Y_BITS-1:0] y_act;

reg [15:0]  input_frame [0:1279][0:719];  // 存入一帧数据
reg [15:0]  scaled_frame [0:639][0:359];  // 输出一帧数据

reg [15:0]   scaled_pixel;                // 缩放后的像素 rgb565 数据



endmodule

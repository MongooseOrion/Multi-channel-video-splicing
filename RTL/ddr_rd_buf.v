/* =======================================================================
* Copyright (c) 2023, MongooseOrion.
* All rights reserved.
*
* The following code snippet may contain portions that are derived from
* OPEN-SOURCE communities, and these portions will be licensed with: 
*
* <NULL>
*
* If there is no OPEN-SOURCE licenses are listed, it indicates none of
* content in this Code document is sourced from OPEN-SOURCE communities. 
*
* In this case, the document is protected by copyright, and any use of
* all or part of its content by individuals, organizations, or companies
* without authorization is prohibited, unless the project repository
* associated with this document has added relevant OPEN-SOURCE licenses
* by github.com/MongooseOrion. 
*
* Please make sure using the content of this document in accordance with 
* the respective OPEN-SOURCE licenses. 
* 
* THIS CODE IS PROVIDED BY https://github.com/MongooseOrion. 
* FILE ENCODER TYPE: GBK
* ========================================================================
*/
// 将 ddr 读出的数据缓存到 buf，并为 hdmi 输出做准备
//
module ddr_rd_buf #(
    parameter DQ_WIDTH  = 12'd32    ,
    parameter H_HEIGHT  = 'd720     ,
    parameter H_WIDTH   = 'd1280              
)(
    input                           clk             ,
    input                           rst             ,

    input                           buf_wr_en       /*synthesis PAP_MARK_DEBUG="1"*/,
    input       [DQ_WIDTH*8-1:0]    buf_wr_data     ,
    output reg                      frame_instruct  ,

    input       [3:0]               ctrl_command_in ,
    input       [3:0]               value_command_in,
    input                           command_flag    ,

    input                           rd_clk          ,
    input                           rd_rst          ,
    input                           rd_en           ,
    input                           rd_fsync        ,
    output reg                      de_o            ,
    output      [15:0]              rgb565_out    /*synthesis PAP_MARK_DEBUG="1"*/
);

parameter WIDTH_QD = H_WIDTH / 4;
parameter HEIGHT_QD = H_HEIGHT / 4;
parameter WIDTH_TC = (H_WIDTH / 4) * 3;
parameter HEIGHT_TC = (H_HEIGHT / 4) * 3;

wire                nege_href       ;
wire                pose_vsync      ;
wire [15:0]         rd_data_fifo    ;
wire                rd_data_final   ;

reg [3:0]           rotate_mode     ;
reg [3:0]           mirror_mode     ;
reg                 rd_fsync_d1     ;
reg                 rd_fsync_d2     ;
reg [2:0]           frame_count     ;
reg                 rd_en_d1        ;
reg                 rd_en_d2        ;
reg [10:0]          row_count       /*synthesis PAP_MARK_DEBUG="1"*/;
reg [19:0]          pix_count       ;
reg [5:0]           wr_addr         ;
reg [9:0]           rd_addr         ;


// 模式控制
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        rotate_mode <= 'b0;
        mirror_mode <= 'b0;
    end
    else if((ctrl_command_in == 4'b0100) && (command_flag == 1'b1)) begin
        if (value_command_in == 'd2) begin   //切换到水平镜像时，先旋转180°
            mirror_mode <= 4'd2; 
            rotate_mode <= 4'd1;
        end
        else if (value_command_in == 4'd0) begin
            mirror_mode <= 4'd0;
            rotate_mode <= 4'd0;            
        end
        else begin
            mirror_mode <= value_command_in;
            rotate_mode <= rotate_mode;
        end
    end
    else begin
        mirror_mode <= mirror_mode;
        rotate_mode <= rotate_mode;        
    end
end


// 帧指示信号
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        rd_fsync_d1 <= 'b0;
        rd_fsync_d2 <= 'b0;
    end
    else begin
        rd_fsync_d1 <= rd_fsync;
        rd_fsync_d2 <= rd_fsync_d1;
    end
end
assign pose_vsync = ((rd_fsync_d1) && (~rd_fsync_d2)) ? 1'b1 : 1'b0;

always @(posedge clk or negedge rst) begin
    if(!rst) begin
        frame_count <= 'b0;
    end
    else if(pose_vsync) begin
        if(frame_count == 3'd4) begin 
            frame_count <= 3'b1;
        end
        else begin
            frame_count <= frame_count + 'd1;
        end
    end
    else begin
        frame_count <= frame_count;
    end
end

always @(posedge clk or negedge rst) begin
    if(!rst) begin
        frame_instruct <= 'b0;
    end
    else if((frame_count == 3'd1) || (frame_count == 3'd2)) begin
        frame_instruct <= 1'b0;
    end
    else if((frame_count == 3'd3) || (frame_count == 3'd4)) begin
        frame_instruct <= 1'b1;
    end
    else begin
        frame_instruct <= frame_instruct;
    end
end


// 正向存储
fifo_rd_buf rd_buf(
    .wr_clk         (clk),                // input
    .wr_rst         ((~rst) || (pose_vsync) || (nege_href)),                // input
    .wr_en          (buf_wr_en),                  // input
    .wr_data        (buf_wr_data),              // input [255:0]
    .wr_full        (),              // output
    .almost_full    (),      // output
    .rd_clk         (rd_clk),                // input
    .rd_rst         ((~rst) || (pose_vsync) || (nege_href)),                // input,每一行读完后，fifo复位
    .rd_en          (rd_en),                  // input
    .rd_data        (rd_data_fifo),              // output [15:0]
    .rd_empty       (),            // output
    .almost_empty   ()     // output
);

// 数据信号
assign rgb565_out = ((pix_count >= WIDTH_TC) && (row_count >= HEIGHT_QD)) ? 16'd0 : rd_data_final;


// 反向存储
ram_rd_buf  reverse_rd_buf(
  .wr_data      (buf_wr_data),    // input [255:0]
  .wr_addr      (wr_addr),    // input [5:0]
  .wr_en        (buf_wr_en),        // input
  .wr_clk       (clk),      // input
  .wr_rst       ((~rst) || (pose_vsync) || (nege_href)),      // input
  .rd_addr      (rd_addr),    // input [9:0]
  .rd_data      (rd_data_ram),    // output [15:0]
  .rd_clk       (rd_clk),      // input
  .rd_rst       ((~rst) || (pose_vsync) || (nege_href))       // input
);


// 反向存储的内部连线
assign rd_data_final = (((rotate_mode == 4'd1 || mirror_mode == 4'd1) &&(mirror_mode != 'd2))
                        && (row_count >= 'd180)) ? rd_data_ram : rd_data_fifo;

always @(posedge clk or negedge rst) begin
    if(!rst) begin
        wr_addr <= 'd0;
    end
    else if((pose_vsync) || (nege_href)) begin   //每次写入一行前写地址清零
        wr_addr <= 'd0;
    end
    else if(buf_wr_en) begin
        wr_addr <= wr_addr + 1'b1;
    end
    else begin
        wr_addr <= wr_addr;
    end
end

always @(posedge rd_clk or negedge rst) begin
    if(!rst) begin
        rd_addr <= 'd0;
    end
    else if((pose_vsync) || (nege_href)) begin //读一行之前地址跳到959
        rd_addr <= WIDTH_TC - 1'b1 ;
    end
    else if(rd_en == 1'b1) begin
        rd_addr <= rd_addr - 1'b1 ;
    end
    else begin
        rd_addr <= rd_addr;
    end
end


// 行像素计数
always @(posedge rd_clk or negedge rd_rst) begin
    if(!rd_rst) begin
        pix_count <= 'b0;
    end
    else if (nege_href == 1'b1) begin
        pix_count <= 'd0;
    end
    else if (de_o == 1'b1) begin
        pix_count <= pix_count + 1'b1;
    end
    else begin
        pix_count <= pix_count;
    end
end


// 读使能（行有效）下降沿
always @(posedge rd_clk or negedge rd_rst) begin
    if(!rd_rst) begin
        rd_en_d1 <= 'b0;
    end
    else begin
        rd_en_d1 <= rd_en;
    end
end
assign nege_href = ((~rd_en) && (rd_en_d1)) ? 1'b1 : 1'b0;


// 读出行数计数
always @(posedge rd_clk or negedge rd_rst) begin
    if(!rd_rst) begin
        row_count <= 'b0;
    end
    else if (pose_vsync) begin
        row_count <= 'b0;
    end
    else if(nege_href) begin
        if(row_count == H_HEIGHT - 1'b1) begin
            row_count <= 11'b0;
        end
        else begin
            row_count <= row_count + 1'b1;
        end
    end
    else begin
        row_count <= row_count;
    end
end


// 输出实际的使能信号
always @(posedge rd_clk or negedge rd_rst) begin
    if(!rd_rst) begin
        de_o <= 'b0;
    end
    else begin
        de_o <= rd_en;
    end
end


endmodule
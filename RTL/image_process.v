/* =======================================================================
* Copyright (c) 2023, MongooseOrion.
* All rights reserved.
*
* The following code snippet may contain portions that are derived from
* OPEN-SOURCE communities, and these portions will be licensed with: 
*
* <GNU General Public License v3.0>
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
// 图像处理模块
// 旋转、缩放、平移
// 
module image_process #(
    parameter MEM_DATA_LEN = 'd64,
    parameter ADDR_LEN = 'd32,
    parameter VIDEO_WIDTH =	'd1024,
    parameter VIDEO_HEIGHT = 'd768,
    parameter BURST_LEN = 'd1
)(
    input 								rst,                  
    input 								clk,                // mem_clk
    input      	[2:0]          			key_out,
    input       [7:0]                   command_in,   	
    // 读通道
    output reg 							rd_valid,           // 读请求
    input 								rd_ready,           // 读数据准备
    output reg 	[9:0] 					rd_burst_len,       // 读突发长度
    output reg 	[ADDR_LEN-1'b1:0]		rd_addr,            // 读首地址
    input      	[MEM_DATA_LEN-1'b1:0]	rd_data,            // 读出的数据
    input 								rd_burst_finish,    // 读完成
    // 写通道
    output reg 							wr_valid,           // 写请求
    input 								wr_ready,           // 写数据准备
    output reg 	[9:0] 					wr_burst_len,       // 写数据长度
    output reg 	[ADDR_LEN-1'b1:0] 		wr_addr,            // 写首地址
    output		[MEM_DATA_LEN-1'b1:0] 	wr_data,            // 写入的数据
    input 								wr_burst_finish,    // 写完成

    output reg							image_addr_flag,
    output reg	[4:0]					function_mode,
    output reg	[15:0]					display_number,
    output reg	[10:0]   				color_threshold,          // 二值化阈值
    output reg 							error
);

// 读写操作状态机参数
parameter   IDLE = 3'd0,
            MEM_READ = 3'd1,
            MEM_WRITE = 3'd2;
// 显示功能模式状态机参数
parameter   DEFAULT_MODE = 5'd0,
            ROTATE_MODE = 5'd1,
            SHIFT_MODE_X = 5'd2,
            SHIFT_MODE_Y = 5'd3,
            SCALE_MODE = 5'd4;

parameter IMAGE_SIZE = VIDEO_HEIGHT * VIDEO_WIDTH;

wire [12:0]	        x_rotate;
wire [12:0]	        y_rotate;
wire				o_en;
wire [12:0]         x_cnt; 
wire [12:0]         y_cnt;

reg [2:0] 	     			state;
reg [7:0] 					wr_cnt;
reg [MEM_DATA_LEN - 1:0] 	wr_data_reg;
reg	[15:0]					wr_data_border;
reg [7:0] 					rd_cnt;
reg [31:0] 					write_read_len;
reg					        i_en;
reg	[10:0]	                angle_temp;
reg	[10:0]	                x_shift_cnt;
reg	[10:0]	                y_shift_cnt;
reg [3:0]	                scale_value;
reg	[10:0]	                angle;
reg	[31:0]	                wr_burst_addr_start;
reg	[31:0]	                rd_burst_addr_start;

assign wr_data = wr_data_reg;
assign x_cnt = write_read_len[9:0];
assign y_cnt = write_read_len[31:10];


// 输入指令处理


// 缩放值的处理
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        scale_value	<= 'b0;
    end
    else if( scale_value == 1 && key_out[1]) begin
        scale_value	<= 4'd6;
    end
    else if( scale_value == 6 && key_out[2])
        scale_value	<=	1;
    else if( function_mode != 4 )		
        scale_value	<=	11'b1;
    else if( key_out[2] && function_mode == 4)
        scale_value	<=	scale_value	+ 11'd1;	
    else if( key_out[1] && function_mode == 4)
        scale_value	<=	scale_value	-	11'd1;
    else begin
        scale_value <= 4'd1;
    end
end


// 划定有效像素的边界，每帧的边界行列均显示特定颜色
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        wr_data_border <= 'd0;
    end
    else if(wr_data_border >= 16'hefff) begin
        wr_data_border <= 16'h1111;
    end
    else if(write_read_len == IMAGE_SIZE) begin
        wr_data_border <= wr_data_border + 16'h1111;
    end
    else begin
        wr_data_border <= 16'h1111;
    end
end


// 对写回的数据进行操作，有效值直接赋值，其他部分置零
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        wr_data_reg <= 'b0;
    end
    // 在缩放模式下，对缩放后的有效像素边界行和列添加特定颜色的边界
    /*else if((x_cnt == VIDEO_WIDTH / scale_value) || (y_cnt == VIDEO_HEIGHT / scale_value)) begin
        wr_data_reg <= {4{wr_data_border}};
    end
    // 在旋转模式下，在行列的中部分别添加特定颜色边界，将屏幕划分为 4 份
    else if(((x_cnt == VIDEO_WIDTH / 2) || (y_cnt == VIDEO_HEIGHT / 2)) && (function_mode == 1)) begin
        wr_data_reg <= {4{wr_data_border}};
    end*/
    else if((y_cnt >= VIDEO_HEIGHT / scale_value) || (x_cnt >= VIDEO_WIDTH / scale_value)) begin
        wr_data_reg <= 'b0;
    end
    else if((x_cnt < x_shift_cnt) || (y_cnt < y_shift_cnt)) begin	
        wr_data_reg <= 'b0;	
    end
    else if((x_rotate > VIDEO_WIDTH) || (y_rotate >= VIDEO_HEIGHT)) begin
        wr_data_reg <= 'hdddd;
    end
    else if((state == MEM_READ) && (rd_ready == 1'b1)) begin
        wr_data_reg <= rd_data;
    end
    else begin
        wr_data_reg <= 'b0;
    end
end


// 
always@(posedge clk or negedge rst)
begin
    if(!rst)
        function_mode	<=	0;
    else if( function_mode == 8 )
        function_mode <= 'b0;
    else if( key_out[0] )
        function_mode	<=	function_mode	+	5'd1;	
end


// 
always@(posedge clk or negedge rst)
begin
    if(!rst)
        angle_temp	<=	9'b0;
    else if( angle_temp == 0 && key_out[1] )
        angle_temp	<=	360;
    else if( angle_temp == 360 && key_out[2] )
        angle_temp	<=	9'b0;
    else if( function_mode != 1 )
        angle_temp	<=	16'b0;
    else if( key_out[2]  && function_mode == 1)
        angle_temp	<=	angle_temp	+	16'd1;	
    else if( key_out[1]  && function_mode == 1)
        angle_temp	<=	angle_temp	-	16'd1;	
end


// 
always@(posedge clk or negedge rst)
begin
    if(!rst)
        x_shift_cnt	<=	0;
    else if( x_shift_cnt == 0 && key_out[1] )
        x_shift_cnt	<=	VIDEO_WIDTH;
    else if( x_shift_cnt == VIDEO_WIDTH && key_out[2] )
        x_shift_cnt	<=	0;	
    else if( function_mode != 2 )
        x_shift_cnt	<=	11'b0;		
    else if( key_out[2] && function_mode == 2 )
        x_shift_cnt	<=	x_shift_cnt	+	11'd5;	
    else if( key_out[1] && function_mode == 2 )
        x_shift_cnt	<=	x_shift_cnt	-	11'd5;
end


// 
always@(posedge clk or negedge rst)
begin
    if(!rst)
        y_shift_cnt	<=	0;
    else if( y_shift_cnt == 0 && key_out[1] )
        y_shift_cnt	<=	VIDEO_HEIGHT;
    else if( y_shift_cnt == VIDEO_HEIGHT && key_out[2] )
        y_shift_cnt	<=	0;	
    else if( function_mode != 3 )
        y_shift_cnt	<=	11'b0;		
    else if( key_out[2] && function_mode == 3 )
        y_shift_cnt	<=	y_shift_cnt	+	11'd5;	
    else if( key_out[1] && function_mode == 3 )
        y_shift_cnt	<=	y_shift_cnt	-	11'd5;
end


// 
always@(posedge clk or negedge rst)
begin
    if(!rst)
        color_threshold	<=	10;
    else if( color_threshold == 10 && key_out[1])
        color_threshold	<=	250;
    else if( color_threshold >= 250 && key_out[2])
        color_threshold	<=	10;
    else if( function_mode != 6 )		
        color_threshold	<=	10;
    else if( key_out[2] && function_mode == 6)
        color_threshold	<=	color_threshold	+	11'd5;	
    else if( key_out[1] && function_mode == 6)
        color_threshold	<=	color_threshold	-	11'd5;
end


always@(posedge clk or negedge rst)
begin
    if(!rst)
        rd_addr 		<='h000000;
    else if( write_read_len == IMAGE_SIZE )
        rd_addr 		<='h000000;
    else case( function_mode )
        0	:	
            rd_addr 	<= 	rd_burst_addr_start	+	write_read_len;
        1	:	
            rd_addr 	<= 	rd_burst_addr_start	+	x_rotate	+	VIDEO_WIDTH*y_rotate;
        2	:	
            rd_addr 	<= 	rd_burst_addr_start	+	x_cnt	+	VIDEO_WIDTH*y_cnt    - x_shift_cnt ;	
        3	:	
            rd_addr 	<= 	rd_burst_addr_start	+	x_cnt	+	VIDEO_WIDTH*y_cnt    -   VIDEO_WIDTH*y_shift_cnt;
        4	:	
            rd_addr 	<= 	rd_burst_addr_start	+	scale_value*x_cnt	+	scale_value*VIDEO_WIDTH*y_cnt;                
        default:	
            rd_addr 	<= 	rd_burst_addr_start	+	write_read_len;	
    
    endcase
end
        
always@(posedge clk or negedge rst)
begin
    if(!rst)
        display_number 		<=0;
    else case( function_mode )
        0	:	
            display_number 	<= 0;
        1	:	
            display_number 	<= 	angle;
        2	:	
            display_number 	<= 	x_shift_cnt ;	
        3	:	
            display_number 	<= 	y_shift_cnt;
        4	:	
            display_number 	<=  scale_value;
        6    :    
            display_number 	<=  color_threshold;
        default:	
            display_number 	<= 0;		
    endcase
end			


coor_trans coor_trans_inst (
    .clk		(	clk			),
    .rst_n		(	rst_n			),
    
    
    .angle		(	angle			),
    .x_in		(	x_cnt			),
    .y_in		(	y_cnt			),
   

    .x_out		(	x_rotate		),
    .y_out		(	y_rotate		)
);




always@(posedge clk or negedge rst)
begin
    if(!rst)
        wr_burst_addr_start	<=32'd6220800 ;
    else if( image_addr_flag )					//image_addr_flag==1
        wr_burst_addr_start	<=32'd4147200 ;
    else	
        wr_burst_addr_start	<=32'd6220800;		//image_addr_flag==0
end

always@(posedge clk or negedge rst)
begin
    if(!rst)
        rd_burst_addr_start	<=32'd2073600;
    else if( image_addr_flag )					//image_addr_flag==1
        rd_burst_addr_start	<=32'd0  ;
    else	
        rd_burst_addr_start	<=32'd2073600;		//image_addr_flag==0
end


always@(posedge clk or negedge rst) begin
    if(!rst) begin
        angle                <=    'b0;
        state 				<= IDLE;
        i_en				<=	1'b1;
        image_addr_flag		<=	1'b0;
        
        wr_valid 		<= 1'b0;
        rd_valid 		<= 1'b0;
        
        rd_burst_len 		<= BURST_LEN;
        wr_burst_len 		<= BURST_LEN;
        
        wr_addr 		<='h000000;
        write_read_len 		<= 32'd0;
    end
    else if( write_read_len == IMAGE_SIZE ) begin
        angle	<=		angle_temp;
        i_en			<=	1'b0;
        state			<=	IDLE;
        write_read_len	<= 	32'd0;
        image_addr_flag	<=	~image_addr_flag;	
        wr_valid 	<=	1'b0;
        rd_valid 	<=	1'b0;		
        wr_addr 	<=	32'd2073600;      
    end
    else begin
        case(state)
            IDLE: begin
                i_en			<=	1'b0;
                state 			<= 	MEM_READ;
                rd_valid 	<= 	1'b1;
            end
            MEM_READ: begin
                if(rd_burst_finish) begin
                    state 			<= 	MEM_WRITE;					
                    rd_valid 	<= 	1'b0;				
                    wr_valid 	<=	1'b1;		
                    wr_addr 	<= 	wr_burst_addr_start  +	x_cnt	+	VIDEO_WIDTH*y_cnt;
                end
            end
            MEM_WRITE: begin
                if(wr_burst_finish)
                begin
                    state 			<=	IDLE;
                    wr_valid 	<=	1'b0;
                    write_read_len 	<= write_read_len +	1'b1;
                    i_en			<=	1'b1;
                end
            end
            default: state <= IDLE;
        endcase
    end
end


endmodule


module osd_display(
	input                       rst_n,   
	input                       pclk,
	input[23:0]                 wave_color,
	input                       adc_clk,
	input                        adc_buf_wr,
	input[11:0]                 adc_buf_addr,
	input[7:0]                  adc_buf_data,
	input                       i_hs,    
	input                       i_vs,    
	input                       i_de,	
	input[23:0]                 i_data,  
	output                      o_hs,    
	output                      o_vs,    
	output                      o_de,    
	output[23:0]                o_data,
    output [10:0]               ram_addr,
    input [7:0]                 q   ,
    input                       udp_rec_data_valid
);
assign ram_addr = osd_ram_addr1[13:3];
assign data = (udp_rec_data_valid==1)?q:8'd0; 
//两区域不能有交叉，否则交叉部分，rom区域会覆盖ram区域，ram区域显示不完整
parameter OSD_WIDTH   =  12'd96;  //更改rom显示区域的大小，要和取的字模的大小一样
parameter OSD_HEGIHT  =  12'd32;
parameter x_start   =  12'd9;  //更改rom显示区域起始位置，要注意剩余的区域不能比显示区域小
parameter y_start  =  12'd9;
parameter color_char  =  24'hff0000;//更改rom区域的字符颜色

parameter OSD_WIDTH1   =  12'd96;  //更改ram显示区域的大小，要和取的字模的大小一样
parameter OSD_HEGIHT1  =  12'd32;
parameter x_start1   =  12'd108;  //更改ram显示区域起始位置，要注意剩余的区域不能比显示区域小
parameter y_start1  =  12'd9;   
parameter color_char1  =  24'hff0000;//更改ram区域的字符颜色

wire[11:0] pos_x;
wire[11:0] pos_y;
wire       pos_hs;
wire       pos_vs;
wire       pos_de;
wire[23:0] pos_data;
reg[23:0]  v_data;
reg[11:0]  osd_x;
reg[11:0]  osd_y;
reg[15:0]  osd_ram_addr;
wire[7:0]  q;
wire[7:0]  q1;
wire[7:0]  data;
reg        region_active;
reg        region_active_d0;
reg        region_active_d1;
reg        region_active_d2;

reg        pos_vs_d0;
reg        pos_vs_d1;

assign o_data = v_data;
assign o_hs = pos_hs;
assign o_vs = pos_vs;
assign o_de = pos_de;
//delay 1 clock 
always@(posedge pclk)
begin
	if(pos_y >= y_start && pos_y <= y_start + OSD_HEGIHT - 12'd1 && pos_x >= x_start && pos_x  <= x_start + OSD_WIDTH - 12'd1)
		region_active <= 1'b1;
	else
		region_active <= 1'b0;
end


always@(posedge pclk)
begin
	region_active_d0 <= region_active;
	region_active_d1 <= region_active_d0;
	region_active_d2 <= region_active_d1;
end

always@(posedge pclk)
begin
	pos_vs_d0 <= pos_vs;
	pos_vs_d1 <= pos_vs_d0;
end

//delay 2 clock
//region_active_d0
always@(posedge pclk)
begin
	if(region_active_d0 == 1'b1)
		osd_x <= osd_x + 12'd1;
	else
		osd_x <= 12'd0;
end


always@(posedge pclk)
begin
	if(pos_vs_d1 == 1'b1 && pos_vs_d0 == 1'b0)
		osd_ram_addr <= 16'd0;
	else if(region_active == 1'b1)
		osd_ram_addr <= osd_ram_addr + 16'd1;
end


always@(posedge pclk)
begin
	if(region_active_d0 == 1'b1)
		if(q1[osd_x[2:0]] == 1'b1)
			v_data <= color_char; //  此处是字符颜色的修改
		else
			v_data <= pos_data;
	else if(region_active1_d0 == 1'b1)
		if(data[osd_x1[2:0]] == 1'b1)
			v_data <= color_char1; //  此处是字符颜色的修改
		else
			v_data <= pos_data;
	else
		v_data <= pos_data;
end

osd_rom osd_rom_m0 (
    .addr(osd_ram_addr[12:3]),
    .clk(pclk),
    .rst(1'b0),
    .rd_data(q1)
);

//ram显示区域***************************************************************************************************************
reg[11:0]  osd_x1;
reg[11:0]  osd_y1;
reg[15:0]  osd_ram_addr1;
reg        region_active1;
reg        region_active1_d0;
reg        region_active1_d1;
reg        region_active1_d2;


//delay 1 clock 
always@(posedge pclk)
begin
	if(pos_y >= y_start1 && pos_y <= y_start1 + OSD_HEGIHT1 - 12'd1 && pos_x >= x_start1 && pos_x  <= x_start1 + OSD_WIDTH1 - 12'd1)
		region_active1 <= 1'b1;
	else
		region_active1 <= 1'b0;
end


always@(posedge pclk)
begin
	region_active1_d0 <= region_active1;
	region_active1_d1 <= region_active1_d0;
	region_active1_d2 <= region_active1_d1;
end

//delay 2 clock
//region_active_d0
always@(posedge pclk)
begin
	if(region_active1_d0 == 1'b1)
		osd_x1 <= osd_x1 + 12'd1;

	else
		osd_x1 <= 12'd0;
end


always@(posedge pclk)
begin
	if(pos_vs_d1 == 1'b1 && pos_vs_d0 == 1'b0)
		osd_ram_addr1 <= 16'd0;
	else if(region_active1 == 1'b1)
		osd_ram_addr1 <= osd_ram_addr1 + 16'd1;
end






//下面实例化了有效位置
timing_gen_xy timing_gen_xy_m0(
	.rst_n    (rst_n    ),
	.clk      (pclk     ),
	.i_hs     (i_hs     ),
	.i_vs     (i_vs     ),
	.i_de     (i_de     ),
	.i_data   (i_data   ),
	.o_hs     (pos_hs   ),
	.o_vs     (pos_vs   ),
	.o_de     (pos_de   ),
	.o_data   (pos_data ),
	.x        (pos_x    ),
	.y        (pos_y    )
);
endmodule
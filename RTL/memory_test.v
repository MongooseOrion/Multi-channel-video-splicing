module memory_test(
    input                  clk_in,
    input                  rstn,

    output reg             init_led,
    output reg [7:0]       data_out,

    output                 wr_full,
    output                 almost_full,
    output                 rd_empty,
    output                 almost_empty
   );

wire        clkout0;
wire        clkout1;
wire        rst;
/*
wire        wr_full;
wire        almost_full;
wire        rd_empty;
wire        almost_empty;*/
wire [7:0]  rd_data;
wire [7:0]  sd_rd_data;


reg         reg_clk_1;
reg         reg_clk_2;
reg         reg_clk_3;
reg [7:0]   generate_data;
reg         data_valid;
reg         rd_en;

reg [8:0]  wr_addr;
reg [8:0]  sd_rd_addr;
reg        sd_wr_en;

assign rst = rstn;

pll u_pll(
   .pll_rst       (1'b0),      // input
   .clkin1        (clk_in),        // input
   .pll_lock      (),    // output
   .clkout0       (clk),      // output
   .clkout1       (clkout1)       // output
);

/*
// 时钟延迟处理
always @(posedge clk or negedge rst) begin
   if(!rst) begin
      reg_clk_1 <= 'b0;
      reg_clk_2 <= 'b0;
      reg_clk_3 <= 'b0;
   end
   else begin
      reg_clk_1 <= ~reg_clk_1;
      reg_clk_2 <= reg_clk_1;
      reg_clk_3 <= reg_clk_2;
   end
end*/

// 生成数据
always @(posedge clkout1 or negedge rst) begin
   if(!rst) begin
      generate_data <= 'b0;
   end
   else begin
      generate_data <= generate_data + 1'b1;
   end
end

always @(posedge clkout1 or negedge rst) begin
   if(!rst) begin
      init_led <= 'b0;
   end
   else if(generate_data > 7'd2) begin
      init_led <= 1'b1;
   end
   else begin
      init_led <= 1'b0;
   end
end

// 数据有效信号
always @(posedge clkout1 or negedge rst) begin
   if(!rst) begin
      data_valid <= 'b0;
   end
   else begin
      data_valid <= 1'b1;
   end
end

fifo u_fifo(
   .clk              (clkout1),                      // input
   .rst              (!rst),                      // input
   .wr_en            (data_valid),                  // input
   .wr_data          (generate_data),              // input [7:0]
   .wr_full          (wr_full),              // output
   .almost_full      (almost_full),      // output
   .rd_en            (rd_en),                  // input
   .rd_data          (rd_data),              // output [7:0]
   .rd_empty         (rd_empty),            // output
   .almost_empty     (almost_empty)     // output
);

// 读数据有效信号
always @(posedge clk or negedge rst) begin
   if(!rst) begin
      rd_en <= 'b0;
   end
   else if(almost_full) begin
      rd_en <= 1'b1;
   end
   else if(almost_empty) begin
      rd_en <= 1'b0;
   end
   else begin
      rd_en <= rd_en;
   end
end
/*
// 读数据延迟一拍处理
always @(posedge clk or negedge rst) begin
   if(!rst) begin 
      data_out <= 'b0;
   end
   else begin
      data_out <= rd_data;
   end
end
*/
// 从 FIFO 中读出的数据写入 SDRAM
sdram u_sdram (
  .wr_data        (rd_data),    // input [7:0]
  .wr_addr        (wr_addr),    // input [8:0]
  .wr_en          (sd_wr_en),        // input
  .wr_clk         (clk),      // input
  .wr_rst         (!rst),      // input
  .rd_addr        (sd_rd_addr),    // input [8:0]
  .rd_data        (sd_rd_data),    // output [7:0]
  .rd_clk         (clk),      // input
  .rd_rst         (!rst)       // input
);

always @(posedge clk or negedge rst) begin
   if(!rst) begin
      sd_wr_en <= 0;
   end
   else if((rd_en) && (wr_addr < 9'd256)) begin
      sd_wr_en <= 1'b1;
   end
   else begin
      sd_wr_en <= 1'b0;
   end
end

always @(posedge clk or negedge rst) begin
   if(!rst) begin
      wr_addr <= 'b0;
   end
   else if(sd_wr_en) begin
      wr_addr <= wr_addr + 1'b1;
   end
   else begin
      wr_addr <= 9'b0;
   end
end

always @(posedge clk or negedge rst) begin
   if(!rst) begin
      sd_rd_addr <= 'b0;
   end/*
   else if(wr_addr == 9'd128) begin
      sd_rd_addr <= 9'd40;
   end
   else if(wr_addr == 9'd256) begin
      sd_rd_addr <= 9'd129;
   end*/
   else if(wr_addr > 9'd3) begin
      sd_rd_addr <= sd_rd_addr + 1'b1;
   end
   else begin
      sd_rd_addr <= 9'd0;
   end
end

always @(posedge clk or negedge rst) begin
   if(!rst) begin 
      data_out <= 'b0;
   end
   else begin
      data_out <= sd_rd_data;
   end
end

endmodule
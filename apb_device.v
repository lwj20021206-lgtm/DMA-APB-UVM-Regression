
module APB_DEVICE(
    pclk,
    presetn,

    paddr,
    pwrite,
    psel,
    penable,
    pwdata,
    prdata,
    pready,

    slave_paddr,
    slave_pwrite,
    slave_psel,
    slave_penable,
    slave_pwdata,
    slave_prdata,
    slave_pready,

    apb_device_int
);

    input            pclk;
    input            presetn;

    input  [31: 0]   paddr;
    input            pwrite;
    input            psel;
    input            penable;
    input  [31: 0]   pwdata;
    output [31: 0]   prdata;
    output           pready;

    output [31: 0]   slave_paddr;
    output           slave_pwrite;
    output           slave_psel;
    output           slave_penable;
    output [31: 0]   slave_pwdata;
    input  [31: 0]   slave_prdata;
    input            slave_pready;

    output           apb_device_int;

    reg    [31: 0]   prdata;
    reg              pready;

    reg    [31: 0]   MEM[0:1023];
    reg    [31: 0]   pready_delay;


    reg    [31: 0]   slave_paddr;
    reg    [31: 0]   slave_pwdata;
    reg              slave_psel;
    reg              slave_penable;
    reg              slave_pwrite;

    reg    [31: 0]   slave_paddr_nxt;
    reg    [31: 0]   slave_pwdata_nxt;
    reg              slave_psel_nxt;
    reg              slave_penable_nxt;
    reg              slave_pwrite_nxt;

    reg    [31: 0]   int_status;

    reg    [31: 0]   prdata_nxt;
    wire             is_dma_reg_read;
    wire             is_dma_read;
    wire             is_dma_write;
    wire             is_dma_copy;
    wire             is_dma_src;
    wire             is_dma_dst;
    wire             is_dma_len;
    wire             is_dma_init;
    wire             is_dma_int;
    wire             is_dma_busy;

    reg              dma_direct_cnt;
    reg              dma_direct_cnt_nxt;
    reg              dma_direct_active;
    reg              dma_init_active;
    reg              dma_copy_active_p1;
    reg              dma_copy_active_p2;
    reg              dma_skip_direct_due_to_early_response;

    initial begin
        for(int i=0;i< 1024;i=i+1) begin
            MEM[i] = 0;
        end
    end

    reg    [27: 0]   dma_src;
    reg    [27: 0]   dma_dst;
    reg    [ 4: 0]   dma_len;
    reg    [31: 0]   dma_int;
    reg    [31: 0]   dma_init_value;

    reg    [31: 0]   dma_int_nxt;
    wire             invalid_op;
    wire             invalid_value_of_length;
    wire             copy_overlap;
    wire             dma_init_copy_done;
    wire   [31: 0]   dma_int_update;

    wire             dma_cnt_push;
    wire             dma_cnt_pop;

    parameter DIRECT_ADDR = 4'b0000;
    parameter DMA_SRC     = 4'b0001;
    parameter DMA_DST     = 4'b0010;
    parameter DMA_LEN     = 4'b0011;
    parameter DMA_INIT    = 4'b0100;
    parameter DMA_COPY    = 4'b1000;
    parameter DMA_INT     = 4'b1111;

//****************************************
//  Function
//****************************************

    assign is_dma_reg_read = pwrite == 0 & ( is_dma_src | is_dma_int | is_dma_len | is_dma_dst );
    assign is_dma_busy     = dma_copy_active_p1 | ( dma_init_active | dma_copy_active_p2 ) & !( ( dma_len == 1 & slave_pready ) | dma_direct_active & !slave_pready);
    assign is_dma_read     = psel & paddr[31:28] == DIRECT_ADDR & pwrite == 0 ;
    assign is_dma_write    = psel & paddr[31:28] == DIRECT_ADDR & pwrite == 1 ;
    assign is_dma_src      = psel & paddr[31:28] == DMA_SRC                   ;
    assign is_dma_dst      = psel & paddr[31:28] == DMA_DST                   ;
    assign is_dma_len      = psel & paddr[31:28] == DMA_LEN                   ;
    assign is_dma_init     = psel & paddr[31:28] == DMA_INIT    & pwrite == 1 ;
    assign is_dma_copy     = psel & paddr[31:28] == DMA_COPY    & pwrite == 1 ;
    assign is_dma_int      = psel & paddr[31:28] == DMA_INT                   ;

//****************************************
//  Interrupt
//****************************************

    assign dma_int_update = {invalid_op, invalid_value_of_length, copy_overlap, dma_init_copy_done};
    assign invalid_op = psel & !( is_dma_read | is_dma_write | is_dma_src | is_dma_len | is_dma_dst | is_dma_init | is_dma_copy | is_dma_int );
    assign dma_init_copy_done = ( dma_init_active | dma_copy_active_p2 ) & slave_pready;
    assign invalid_value_of_length = is_dma_len & pready & ( pwdata == 0 | pwdata > 16 );
    assign copy_overlap = is_dma_copy & ( (( dma_len + dma_src ) > dma_dst & ( dma_src < dma_dst )) | (( dma_src > dma_dst ) & ((dma_dst + dma_len ) > dma_src )) );

    assign apb_device_int = |dma_int;

    always@(*) begin
        if ( is_dma_int && pwrite && pready )
            dma_int_nxt = dma_int & ~pwdata;
        else if ( |dma_int_update )
            dma_int_nxt = dma_int | dma_int_update;
    end


//****************************************
//  Normal Register
//****************************************

    assign dma_cnt_push = ( is_dma_read | is_dma_write | dma_direct_active & !dma_direct_cnt ) & pready;//dma_direct_active & !is_dma_busy;
    assign dma_cnt_pop = dma_direct_active & slave_pready;

    always@(*) begin
        case({dma_cnt_push, dma_cnt_pop})
        2'b00     :    dma_direct_cnt_nxt = dma_direct_cnt;
        2'b01     :    dma_direct_cnt_nxt = ~dma_direct_cnt;
        2'b10     :    dma_direct_cnt_nxt = ~dma_direct_cnt;
        2'b11     :    dma_direct_cnt_nxt = dma_direct_cnt;
        endcase
    end

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn )
            dma_direct_cnt <= 0;
        else if ( dma_cnt_push || dma_cnt_pop )
            dma_direct_cnt <= dma_direct_cnt_nxt;
    end

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn )
            dma_direct_active <= 0;
        else if ( dma_direct_active && slave_pready == 1 )
            dma_direct_active <= 0;
        else if ( ( is_dma_read || is_dma_write ) && !dma_direct_cnt && !is_dma_busy )
            dma_direct_active <= 1;
    end

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn )
            dma_init_active <= 0;
        else if ( is_dma_init && pready == 1 )
            dma_init_active <= 1;
        else if ( dma_init_active && slave_pready == 1 && dma_len == 1)
            dma_init_active <= 0;
    end

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn )
            dma_copy_active_p1 <= 0;
        else if ( is_dma_copy && pready == 1 )
            dma_copy_active_p1 <= 1;
        else if ( dma_copy_active_p2 && slave_pready == 1 && dma_len > 1 )
            dma_copy_active_p1 <= 1;
        else if ( dma_copy_active_p1 && slave_pready == 1 )
            dma_copy_active_p1 <= 0;
    end

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn )
            dma_copy_active_p2 <= 0;
        else if ( dma_copy_active_p1 && slave_pready == 1 )
            dma_copy_active_p2 <= 1;
        else if ( dma_copy_active_p2 && slave_pready == 1 )
            dma_copy_active_p2 <= 0;
    end

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn )
            dma_src <= 0;
        else if ( is_dma_src && pwrite == 1 && pready == 1 )
            dma_src <= pwdata;
        else if ( ( dma_copy_active_p1 || dma_init_active ) && slave_psel && !slave_penable )
            dma_src <= dma_src + 1;
    end

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn )
            dma_dst <= 0;
        else if ( is_dma_dst && pwrite == 1 && pready == 1 )
            dma_dst <= pwdata;
        else if ( dma_copy_active_p2 && slave_pready == 1 )
            dma_dst <= dma_dst + 1;
    end

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn )
            dma_len <= 0;
        else if ( is_dma_len && pwrite == 1 && pready == 1 )
            dma_len <= pwdata;
        else if ( ( dma_init_active || dma_copy_active_p2 ) && slave_pready == 1 )
            dma_len <= dma_len -1;
    end

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn )
            dma_init_value <= 0;
        else if ( is_dma_init && pwrite == 1 && pready == 1 )
            dma_init_value <= pwdata;
        else if ( dma_copy_active_p1 && slave_pready == 1 )
            dma_init_value <= slave_prdata;
    end

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn )
            dma_int <= 0;
        else if ( dma_int_update )
            dma_int <= dma_int_nxt;
        else if ( is_dma_int && pwrite == 1 && pready == 1 )
            dma_int <= dma_int_nxt;
    end

    always@(*) begin
        if ( is_dma_reg_read )
        case(paddr[31:28])
        DMA_SRC : prdata_nxt = dma_src;
        DMA_DST : prdata_nxt = dma_dst;
        DMA_LEN : prdata_nxt = dma_len;
        DMA_INT : prdata_nxt = dma_int;
        endcase
    end


//****************************************
//  Slave APB interface
//****************************************

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn ) begin
            slave_paddr  <= 0;
            slave_psel   <= 0;
            slave_pwrite <= 0;
            slave_pwdata <= 0;
        end
        else if ( ( ( is_dma_read | is_dma_write & !is_dma_busy ) & !is_dma_busy & !dma_direct_active | dma_init_active | dma_copy_active_p1 | dma_copy_active_p2 ) && !(slave_psel & !slave_pready) || slave_pready ) begin
            slave_paddr  <= slave_paddr_nxt;
            slave_psel   <= slave_psel_nxt;
            slave_pwrite <= slave_pwrite_nxt;
            slave_pwdata <= slave_pwdata_nxt;
        end
    end

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn )
            slave_penable <= 0;
        else if ( slave_psel | slave_pready )
            slave_penable <= slave_psel & !slave_pready;
    end


//****************************************
//  DMA Read
//****************************************

    always@(*) begin
        if ( ( is_dma_read || is_dma_write ) && !is_dma_busy && !dma_direct_active && !dma_direct_cnt) begin
            slave_paddr_nxt  = paddr[27:0];
            slave_psel_nxt   = psel;
            slave_pwrite_nxt = pwrite;
            slave_pwdata_nxt = pwdata;
        end
        else if ( dma_init_active && !( dma_len == 1 & slave_pready ) ) begin
            slave_paddr_nxt  = dma_src;
            slave_psel_nxt   = 1;
            slave_pwrite_nxt = 1;
            slave_pwdata_nxt = dma_init_value;
        end
        else if ( dma_copy_active_p1 & !slave_pready || dma_copy_active_p2 && slave_pready && dma_len != 1 ) begin
            slave_paddr_nxt  = dma_src;
            slave_psel_nxt   = 1;
            slave_pwrite_nxt = 0;
            slave_pwdata_nxt = 0;
        end
        else if ( dma_copy_active_p1 && slave_pready ) begin
            slave_paddr_nxt  = dma_dst;
            slave_psel_nxt   = 1;
            slave_pwrite_nxt = 1;
            slave_pwdata_nxt = slave_prdata;
        end
        else begin
            slave_paddr_nxt  = $urandom_range(0, (1 << 32) -1);
            slave_psel_nxt   = 0;
            slave_pwrite_nxt = $urandom_range(0, 1);
            slave_pwdata_nxt = $urandom_range(0, (1 << 32) -1);
        end
    end

//****************************************
//  Master APB Interface
//****************************************

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn )
            prdata <= 0;
        else if ( is_dma_read & slave_psel & slave_penable & slave_pready )
            prdata <= slave_prdata;
        else if ( is_dma_reg_read )
            prdata <= prdata_nxt;
    end

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn )
            pready_delay <= 0;
        else if ( psel & !penable )
            pready_delay <= $urandom_range(0, 9);
        else if ( psel & penable & pready_delay !=0 )
            pready_delay <= pready_delay - 1;
    end

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn)
            pready<= 0;
        else if ( pready )
            pready<= 0;
        else if ( is_dma_read & slave_psel & slave_penable & !dma_direct_cnt & slave_pready & !( dma_init_active | dma_copy_active_p2 | dma_copy_active_p1 ))
            pready<= 1;
        else if ( !is_dma_read & psel & penable & pready_delay == 0 & !is_dma_busy )
            pready<= 1;
    end

    property P1 ;
        @(posedge pclk)  disable iff (!presetn) ( psel == 1'b0) |-> ~penable ;
    endproperty

    property P2 ;
        @(posedge pclk)  disable iff (!presetn) ( $past(psel) == 0 & psel == 1 |-> ~penable ) ;
    endproperty

    property P3 ;
        @(posedge pclk)  disable iff (!presetn) ( $past(psel) == 1 & $past(pready) == 0 & psel == 1 |-> penable ) ;
    endproperty

    property P4 ;
        @(posedge pclk)  disable iff (!presetn) ( psel && ~penable ) |=> $stable(pwrite) ;
    endproperty

    property P5 ;
        @(posedge pclk)  disable iff (!presetn) ( psel && ~penable ) |=> $stable(paddr) ;
    endproperty

    property P6 ;
        @(posedge pclk)  disable iff (!presetn) ( psel && ~penable ) |=> $stable(pwdata) ;
    endproperty

    MTK_APB_AIP_CON1 : assert property(P1);
    MTK_APB_AIP_CON2 : assert property(P2);
    MTK_APB_AIP_CON3 : assert property(P3);
    MTK_APB_AIP_CON4 : assert property(P4);
    MTK_APB_AIP_CON5 : assert property(P5);
    MTK_APB_AIP_CON6 : assert property(P6);

`ifdef APB_DEVICE_LEGACY_SELFTEST
    reg [31: 0] random_cnt;
    reg [31: 0] pre_addr;
    reg [31: 0] golden_data;

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn )
            pre_addr <= 0;
        else if (psel && penable && pready)
            pre_addr <= paddr;
    end

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn )
            golden_data <= 0;
        else if (psel && penable && pready && pwrite == 0 && random_cnt == 10 )
            golden_data <= prdata;
    end

    always@(posedge pclk or negedge presetn) begin
        if ( ~presetn)
            random_cnt <= 0;
        else if ( psel && penable && pready )
            random_cnt <= random_cnt+1;
    end

    reg invalid_op_chk;

    always@(*) begin
        if ( random_cnt < 11 )
        if ( psel & penable & pready ) begin

            case( {paddr[31:28]})
            4'b0101     :    invalid_op_chk = 1;
            4'b0110     :    invalid_op_chk = 1;
            4'b0111     :    invalid_op_chk = 1;
            4'b1001     :    invalid_op_chk = 1;
            4'b1010     :    invalid_op_chk = 1;
            4'b1011     :    invalid_op_chk = 1;
            4'b1100     :    invalid_op_chk = 1;
            4'b1101     :    invalid_op_chk = 1;
            4'b1110     :    invalid_op_chk = 1;
            default     :    invalid_op_chk = 0;
            endcase
            if ( invalid_op_chk ) begin
                $display("Simulation Failed. Invalid Operation. Addr[31:28] = %0b.", paddr[31:28]);
                $finish;
            end
        end
    end

    always@(*) begin
        if ( random_cnt != 0 && random_cnt < 11 )
        if ( psel & penable & pready )
        if ( paddr == pre_addr ) begin
            $display("Simulation Failed. Address of APB-transfer[%0d] is the same with address of APB-transfer[%0d].", random_cnt+1, random_cnt);
            $finish;
        end
    end

    always@(*) begin
        if ( random_cnt == 10 && psel && penable && pready ) begin
            if ( pwrite ) begin
                $display("Simulation Failed. 1st specified APB transfer should be an APB read transfer.");
                $finish;
            end
            if ( paddr != 'habcd ) begin
                $display("Simulation Failed. address of 1st specified APB transfer should be 'habcd.");
                $finish;
            end
        end
    end

    always@(*) begin
        if ( random_cnt == 11 )
        if ( pwrite & psel & penable & pready ) begin
            if ( !pwrite ) begin
                $display("Simulation Failed. 1st specified APB transfer should be an APB write transfer.");
                $finish;
            end
            if ( paddr != 'habcd ) begin
                $display("Simulation Failed. address of 2nd specified APB transfer should be 'habcd.");
                $finish;
            end
            if ( pwdata == golden_data + 1 )
                $display("Simulation Passed.");
            else
                $display("Simulation Failed. Expected Write data is %0x, but current write data is %0x.", (golden_data + 1), pwdata);
        end
    end
`endif

endmodule

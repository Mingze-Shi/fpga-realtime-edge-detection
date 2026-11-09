`timescale 1ns/1ps
// Descriptor-level test. This does not replace an AXI memory-controller test:
// wr_sw/rd_sw denote the existing controller bank boundaries, not B/R completion.
module frame_freeze_tb;
    localparam FRAME_BYTES = 16 * 8 * 32 / 8 + 32'h200;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg wr_sw = 1'b0, rd_sw = 1'b0, freeze_request = 1'b0;
    wire [1:0] wr_bank, rd_bank;
    wire wr_sw_ack, rd_sw_ack;
    wire [31:0] wr_start_addr, rd_start_addr;

    bank_switch #(
        .FB_NUM(3), .MAX_VID_WIDTH(16), .MAX_VID_HIGHT(8),
        .START_ADDR(0), .VID_DATA_WIDTH(32), .AXI_DATA_WIDTH(256)
    ) dut (
        .ddr_clk(clk), .rst_n(rst_n), .wr_sw(wr_sw), .rd_sw(rd_sw),
        .freeze_request(freeze_request),
        .wr_bank(wr_bank), .rd_bank(rd_bank),
        .wr_sw_ack(wr_sw_ack), .rd_sw_ack(rd_sw_ack),
        .wr_start_addr(wr_start_addr), .rd_start_addr(rd_start_addr)
    );

    reg [1:0] previous_wr_bank, previous_rd_bank;
    reg previous_wr_sw = 1'b0, previous_rd_sw = 1'b0;
    integer wr_boundary_window = 0, rd_boundary_window = 0;
    integer checks = 0, frame_serial = 0;
    integer slot_tag [0:2];
    reg enforce_frozen = 1'b0;
    reg [1:0] pinned_bank;
    integer pinned_tag;
    reg [31:0] pinned_address;

    // Check externally observable ownership and address arithmetic on EVERY cycle.
    // A short window permits a serialized/pending simultaneous-request handler.
    always @(posedge clk) begin
        if (!rst_n) begin
            previous_wr_sw = 1'b0;
            previous_rd_sw = 1'b0;
            wr_boundary_window = 0;
            rd_boundary_window = 0;
            #1;
            previous_wr_bank = wr_bank;
            previous_rd_bank = rd_bank;
        end else begin
            if (wr_sw && !previous_wr_sw) begin
                wr_boundary_window = 5;
                frame_serial = frame_serial + 1;
                if (enforce_frozen && wr_bank == pinned_bank)
                    $fatal(1, "writer targets the pinned frame before its switch");
                slot_tag[wr_bank] = frame_serial;
            end else if (wr_boundary_window > 0)
                wr_boundary_window = wr_boundary_window - 1;
            if (rd_sw && !previous_rd_sw)
                rd_boundary_window = 5;
            else if (rd_boundary_window > 0)
                rd_boundary_window = rd_boundary_window - 1;
            previous_wr_sw = wr_sw;
            previous_rd_sw = rd_sw;
            #1;
            if (wr_bank > 2 || rd_bank > 2)
                $fatal(1, "illegal frame slot wr=%0d rd=%0d", wr_bank, rd_bank);
            if (wr_bank == rd_bank)
                $fatal(1, "read/write slot collision at %0t: slot %0d", $time, wr_bank);
            if (wr_start_addr !== wr_bank * FRAME_BYTES ||
                rd_start_addr !== rd_bank * FRAME_BYTES)
                $fatal(1, "frame-slot/address disagreement");
            if (wr_bank !== previous_wr_bank && wr_boundary_window == 0)
                $fatal(1, "writer moved without a write-bank boundary");
            if (rd_bank !== previous_rd_bank && rd_boundary_window == 0)
                $fatal(1, "reader moved without a read-bank boundary");
            if (enforce_frozen) begin
                if (rd_bank !== pinned_bank || rd_start_addr !== pinned_address)
                    $fatal(1, "frozen read descriptor changed");
                if (wr_bank == pinned_bank || slot_tag[pinned_bank] != pinned_tag)
                    $fatal(1, "frozen image was overwritten");
            end
            previous_wr_bank = wr_bank;
            previous_rd_bank = rd_bank;
            checks = checks + 1;
        end
    end

    task tick;
        input integer count;
        integer j;
        begin
            for (j = 0; j < count; j = j + 1) begin
                @(posedge clk); #2;
            end
        end
    endtask

    task pulses;
        input write_pulse, read_pulse;
        begin
            @(negedge clk);
            wr_sw = write_pulse;
            rd_sw = read_pulse;
            tick(2);
            @(negedge clk);
            wr_sw = 1'b0;
            rd_sw = 1'b0;
            tick(6);
        end
    endtask

    task reset_design;
        integer k;
        begin
            @(negedge clk);
            enforce_frozen = 1'b0;
            rst_n = 1'b0;
            wr_sw = 1'b0;
            rd_sw = 1'b0;
            freeze_request = 1'b0;
            for (k = 0; k < 3; k = k + 1)
                slot_tag[k] = -1;
            tick(5);
            @(negedge clk); rst_n = 1'b1;
            tick(6);
            if (wr_bank !== 0 || rd_bank !== 1)
                $fatal(1, "reset did not restore initial frame ownership");
        end
    endtask

    integer i;
    integer saved_tag;
    reg [1:0] retained_clean, private_writer, old_read;
    reg [31:0] saved_rd_address;
    reg [31:0] random_state = 32'h9e3779b9;
    initial begin
        reset_design;
        pulses(1'b1, 1'b0);
        if (wr_bank !== 2 || rd_bank !== 1)
            $fatal(1, "first capture did not use the spare slot");
        pulses(1'b0, 1'b1);
        if (rd_bank !== 0)
            $fatal(1, "normal replay did not select the completed clean slot");

        // Assert between boundaries; a key event must not change a DDR address.
        saved_rd_address = rd_start_addr;
        @(negedge clk); #2; freeze_request = 1'b1;
        tick(8);
        if (rd_start_addr !== saved_rd_address)
            $fatal(1, "freeze request changed a read address between boundaries");
        pulses(1'b0, 1'b1);
        pinned_bank = rd_bank;
        pinned_address = rd_start_addr;
        pinned_tag = slot_tag[pinned_bank];
        if (pinned_tag < 0)
            $fatal(1, "freeze selected an image that was never captured");
        enforce_frozen = 1'b1;

        // First capture uses the remaining spare; later captures reuse only the
        // private writer slot. The earlier clean slot must remain available.
        retained_clean = wr_bank;
        pulses(1'b1, 1'b0);
        private_writer = wr_bank;
        saved_tag = slot_tag[retained_clean];
        if (private_writer == retained_clean || private_writer == pinned_bank)
            $fatal(1, "freeze did not preserve three distinct ownership roles");
        for (i = 0; i < 36; i = i + 1) begin
            pulses(1'b1, (i % 3) == 0);
            pulses(1'b0, 1'b1);
            if (wr_bank !== private_writer || slot_tag[retained_clean] != saved_tag)
                $fatal(1, "private writer/retained clean ownership changed while frozen");
        end
        tick(25);

        // Release changes nothing until a read boundary. Minimal pinning resumes
        // from retained clean, then returns to fresh capture on the next rotation.
        enforce_frozen = 1'b0;
        @(negedge clk); #3; freeze_request = 1'b0;
        tick(8);
        if (rd_bank !== pinned_bank)
            $fatal(1, "resume changed bank outside a replay boundary");
        pulses(1'b0, 1'b1);
        if (rd_bank !== retained_clean || slot_tag[rd_bank] != saved_tag)
            $fatal(1, "resume lost the retained complete image");
        pulses(1'b1, 1'b0);
        pulses(1'b0, 1'b1);
        if (rd_bank !== private_writer)
            $fatal(1, "resume did not return to newly captured frames");

        // The old design's writer-priority else-if loses this read edge.
        // An existing clean image must still be consumed when both edges arrive.
        reset_design;
        pulses(1'b1, 1'b0); // clean = 0, writer = 2, reader = 1, no spare.
        pulses(1'b1, 1'b1);
        if (rd_bank !== 0)
            $fatal(1, "simultaneous write/read boundary lost the pending read request");

        // Freeze during active ownership, then reset while pinned.
        @(negedge clk); freeze_request = 1'b1;
        tick(8);
        pulses(1'b0, 1'b1);
        pinned_bank = rd_bank;
        pinned_address = rd_start_addr;
        pinned_tag = slot_tag[pinned_bank];
        enforce_frozen = 1'b1;
        pulses(1'b1, 1'b1);
        reset_design;

        // Arbitrary phase/event combinations check address stability, legal slots,
        // and reader/writer exclusion independently of a fixed expected sequence.
        for (i = 0; i < 300; i = i + 1) begin
            random_state = {random_state[30:0],
                random_state[31] ^ random_state[21] ^ random_state[1] ^ random_state[0]};
            if (random_state[5:3] == 3'b101) begin
                @(negedge clk); #1; freeze_request = ~freeze_request;
                tick(7);
            end
            pulses(random_state[0], random_state[1]);
        end
        $display("PASS: DDR frame ownership, synchronized freeze, repeated single-frame replay, retained-image integrity, safe resume, simultaneous boundaries, reset and randomized bank/address checks (%0d cycles).", checks);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "frame freeze test timed out");
    end
endmodule

;
; Calculator.asm
; Version 1.0
; 
; 
; Writen By Bulbul
; 2024 June In Zibo
;
;
; Release Record:
;     Version 1  --  2024.6.19 19:26
; 
; 
; Description: 
;     Basic 16 bit calculator. 
;     When you start the programme, LCD12864 will play a animation first,
;     then, the screen will display the welcome information.
;     When you are using this calculator, if you have calculated current
;     expression, you just continue to enter next expression, the programme
;     will automatic to process.
;     
;     Function key:
;           + F1  --  Delete: Delete latest input. (**NOT ACCOMPLISH**)
;           + F2  --  Clear:  Clear current input. (**NOT ACCOMPLISH**)
;           + F3  --  Reset:  Clear screen and all buffer, initial calculator. (**NOT ACCOMPLISH**)
;           + F4  --  Equal:  Calculate result of expression.
;
;     Operator key:
;           + A  --  Operator +
;           + B  --  Operator -
;           + C  --  Operator * 
;           + D  --  Operator / 
;           + E  --  Operator ) 
;           + F  --  Operator ( 
;
;
; Features:
;      + Support + - * / and `(` `)` operation.
;      + Support priority judge.      
;      + Support clear screen.
;      
;     
; Hardware Requirement:
;      1. 8086/8088
;      2. 8255
;      3. LCD12864
;      4. 4*5 Keyboard
;     
; 
; TODO:
;      1. Accomplish all function key. 
;      2. Add error management module.
; 
; 
; Update Records:
;     2024.6.17 13:36  --  Finish two core algrithms.
;     2024.6.18 03:53  --  Finish trans decimal to string (prepare for display).
;     2024.6.18 23:53  --  Finish basic function(Besides function key).
;     2024.6.19 14:00  --  Finish hardware connection testing.
;                       |  Add start animation and welcome infomation.
;                       |  Fix some bugs.
;     2024.6.19 19:23  --   Rename some label.
;                       |   Add some comment.
;                       |   Tidy code.
; 
;


LCD     equ 0360h
wricode equ LCD+0       ;写命令
wrdata  equ LCD+1       ;写数据
rdstat  equ LCD+2       ;读状态
rddata  equ LCD+3       ;读数据

DDRAM   equ 80h         ; LCD Start

LINE1_S equ DDRAM+00H   ; Line1 Start
LINE1_E equ DDRAM+07H   ; Line1 End

LINE2_S equ DDRAM+10H   ; Line2 Start
LINE2_E equ DDRAM+17H   ; Line3 End

LINE3_S equ DDRAM+08H   ; Line3 Start
LINE3_E equ DDRAM+0FH   ; Line3 End

DIS_RES equ DDRAM+18H   ; Line4 Start

CS8255  equ 02dfh      ;8255命令控制口, 写入 89H, Port A Port B 输出, PortC 输入
outbit  equ 02ddh      ;键扫控制口 low 2 bit is 01, Port B, write
inkey   equ 02deh      ;键盘读入口 low 2 bit is 10, Port C, read

; Key id mapping
ADD_ID  equ 10          ; Add +
SUB_ID  equ 11          ; Sub -
MUL_ID  equ 12          ; Mul *
DIV_ID  equ 13          ; Div /
RBRACE  equ 14          ; right brace )
LBRACE  equ 15          ; Left brace (

data segment

      ;============= Logic control module =============
      ; Animation frame
      RAIN1                   DB "     **  **     "
                              DB "    /  /  /     "
                              DB "  (**********)  "
                              DB "     /   /      "
           
      RAIN2                   DB "     **  **     "
                              DB "     /   /      "
                              DB "  (**********)  "
                              DB "    /  /  /     "
      
      ; Welcome infomation
      Welcome                 DB "简易计算器  v1.0"
                              DB "2024 Jun In Zibo"
                              DB "Writen By Bulbul"
                              DB "请输入表达式...."

      cal_finish_prompt       db "Calculate finish!", 0dh, 0ah,'$'
      cal_error_prompt        db 'Calculate Error', 0dh, 0ah,'$'
      input_error_prompt      db 'Input Invalid', 0dh, 0ah,'$'

      calculate_flag          db 1                                      ; mark does epxression calculate or not
      ;============= Logic control module =============


      ;============= Keboard input module =============
      ;Keyboard definition, layout as same as actual layout(be flipped)
      key_mapping             db 13h,0dh,0eh,0fh,00h,?,?,?
                              db 12h,0ch,03h,02h,01h,?,?,?
                              db 11h,0bh,06h,05h,04h,?,?,?
                              db 10h,0ah,09h,08h,07h,?,?,?

      shake_key               db ?
      shake_count             db ?
      ;============= Keboard input module =============

      
      ;============= LCD display module =============
      lcd_cursor              db 0                                      ; LCD cursor postion, only expression area

      str_number_buffer       db 300 dup(?)                             ; character stack, prepare for display ans
      str_number_buffer_count dw 0                                      ; length of buffer
      ;============= LCD display module =============


      ;============= Expression parse module =============
      digital_buffer          dw 0                                      ; current input digital, true value not character
      digital_buffer_count    db 0                                      ; length of current digital

      operator_stack          db 100 dup(?)                             ; operator stack, serve for trans postfix
      operator_stack_index    db 0                                      ; stack index, always point an empty hole

      postfix_buffer          dw 300 dup(?)                             ; store current expression's postfix
      postfix_buffer_count    dw 0                                      ; length of postfix

      ;============= Expression parse module =============
    

      ;============= Expression calculate module =============
      calculate_stack         dw 200 dup(?)                             ; maintain the number stack when final calculate result
      calculate_stack_index   dw 0                                      ; stack index, always poitn an empty hole

      final_result            dw 0                                      ; calculate result of current expression
      ;============= Expression calculate module =============

data ends

code segment
                             assume cs:code,ds:data
      start:                 mov    ax,data
                             mov    ds,ax

                             call   initial

                             call   miss_rain

                             call   display_welcome

      calculate_main:        
          
      next_char:             
                             call   scan_debounce
                             cmp    cl,20h                             ; keyboard no input

                             je     next_char                          ; loop

      ; judeg is previous expression finish calculate or not
                             cmp    calculate_flag, 1
                             je     cls_for_next_cal

      ; judge funciton key first
      judge_function_key:    cmp    al, 16                             ;F1
                             je     delete

                             cmp    al, 17                             ;F2
                             je     clear

                             cmp    al, 18                             ;F3
                             je     reset

                             cmp    al, 19                             ;F4
                             je     calculate
     
      ; push input to LCD, cl default store input info
                             call   display_single_char

      ; judge number or operator
                             cmp    al, 9
                             jbe    digital                            ;0-9
            
                             cmp    al, 15
                             jbe    operator                           ;A-F, +-*/()

      ; input invalid
      ; TODO: Add a error process module
      input_error:           
                             call   display_error
                             jmp    end_start
      digital:               
                             call   update_number
                             jmp    next_char
 
      operator:              
                             call   store_number                       ; Store number to postfix at first

                             call   process_operator                   ; process operator
                             jmp    next_char

      ; TODO: This function is not accomplish
      delete:                                                          ; delete one charater from current expression
                             call   delete_single_char

                             jmp    next_char

      ; TODO: This function is not accomplish
      clear:                 
      ; only clear currect input data
                             call   clear_current_input
   
                             jmp    next_char

      reset:                 
      ; Reset all data about calculate

                             call   reset_cal

                             jmp    next_char

      calculate:             
      
                             call   store_number                       ; Store number first
                             call   empty_op_stk                       ; Empty operator stack
                             call   calculate_postfix                  ; Calculate final result
                             call   display_final_result               ; Print result to LCD

                             mov    calculate_flag, 1                  ; mark calculate finish

                             jmp    next_char
                             
      cls_for_next_cal:      
                             call   reset_cal
                             mov    calculate_flag, 0                  ; initial flag
                             jmp    judge_function_key

      end_start:             
                             mov    ah, 4ch
                             int    21h


      ; Display welcome infomation
      ; Parameter :  None
display_welcome proc
                             push   bx
                             push   ax
                             push   cx

                             mov    al, 01h                            ;清除显示
                             call   draw_rain_wc
                             
                             mov    al, DDRAM                          ;写ddram，data display ram，指向开始
                             call   draw_rain_wc

                             mov    BX,OFFSET Welcome                  ;显示汉字和字符
                             mov    AH,40H

      next_welcom:           mov    AL,00H
                             xlat                                      ; AL = [BX+AL], 这里等价于获取 [BX] 的值
                             call   draw_rain_wd
                             inc    BX
                             dec    AH
                             jnz    next_welcom

                             pop    cx
                             pop    ax
                             pop    bx

                             ret
display_welcome endp

      ; Display rain animation, repeat 3 times
      ; Parameter :  None
miss_rain proc
                             push   bx
                             push   ax
                             push   cx
                             
                             mov    cx, 3
      start_draw:            
                             mov    al, 01h                            ;清除显示
                             call   draw_rain_wc
                             
                             mov    al, DDRAM                          ;写ddram，data display ram，指向开始
                             call   draw_rain_wc

                             mov    bx, offset RAIN1                   ;显示汉字和字符
                             mov    ah, 40h

      next_1:                mov    al, 00h
                             xlat                                      ; AL = [BX+AL], 这里等价于获取 [BX] 的值
                             call   draw_rain_wd
                             inc    bx
                             dec    ah
                             jnz    next_1

                             call   delay_l
                             
                             mov    al, 01h                            ;清除显示
                             call   draw_rain_wc

                             mov    al, DDRAM                          ;写ddram，data display ram，指向开始
                             call   draw_rain_wc


                             mov    bx, offset RAIN2                   ;显示汉字和字符
                             mov    ah, 40H

      next_2:                mov    al,00H
                             xlat                                      ; AL = [BX+AL], 这里等价于获取 [BX] 的值
                             call   draw_rain_wd
                             inc    bx
                             dec    ah
                             jnz    next_2

                             call   delay_l

                             loop   start_draw

                             pop    cx
                             pop    ax
                             pop    bx
                             ret
miss_rain endp

      ; LCD 12864 : Write data to LCD -- Short delay
      ; Parameter :
      ;             AL  --  Which character you want to display
draw_rain_wd proc near
                             push   dx
                             call   delay_s
                             mov    dx, wrdata
                             out    dx, al
                             pop    dx
                             ret
draw_rain_wd endp

      ; LCD 12864 : Write command to LCD -- Short delay
      ; Parameter :
      ;             AL  --  Which command you want to display
draw_rain_wc proc near
                             push   dx
                             call   delay_s
                             mov    dx, wricode
                             out    dx, al
                             pop    dx
                             ret
draw_rain_wc endp

      ; Sort delay funtion
      ; Parameter :  None
delay_s proc near
                             push   cx
                             mov    cx, 0080h
                             loop   $
                             pop    cx
                             ret
delay_s endp


      ; Long delay funtion
      ; Parameter :  None
delay_l proc near
                             push   cx
                             mov    cx, 00800h
      next_delay_s:          
                             call   delay_s
                             loop   next_delay_s
                             pop    cx
                             ret
delay_l endp


      ; Reset all buffer and clear LCD. Initial calculator
      ; Parameter :  None
reset_cal proc
                             push   ax

                             mov    lcd_cursor, 0
                             mov    final_result, 0
                             mov    digital_buffer_count, 0
                             mov    operator_stack_index, 0
                             mov    postfix_buffer_count, 0
                             mov    calculate_stack_index, 0
                             mov    str_number_buffer_count, 0

                             mov    al,01h                             ;清除显示
                             call   write_cmd

                             pop    ax
                             ret
reset_cal endp

      ; Judge whether current cursor position needs adjustment after deleting character.
      ; Parameter :  None
adjust_cursor_del proc

                             push   ax
      ; first to judge need change line or not
                             cmp    lcd_cursor, 15                     ; from 16 to 15
                             je     adjust_l1_e                        ; line from 2 to 1

                             cmp    lcd_cursor, 31                     ; from 32 to 31
                             je     adjust_l2_e                        ; line from 3 to 2

                             cmp    lcd_cursor, 47                     ; from 48 to 47
                             je     adjust_l3_e                        ; line from 1 back to 3

      ; Normal case, update LCD DDRAM
                             mov    al, lcd_cursor
                             add    al, DDRAM
                             call   write_cmd
      finish_adjust_del:     
                             pop    ax
                             ret


      adjust_l1_e:           
                             mov    al, LINE1_E                        ; point to line 1
                             call   write_cmd

                             jmp    finish_adjust_del

      adjust_l2_e:           
                             mov    al, LINE2_E                        ; point to line 2
                             call   write_cmd

                             jmp    finish_adjust_del

      adjust_l3_e:           
                             mov    al, LINE3_E                        ; point to line 3
                             call   write_cmd

                             jmp    finish_adjust_del
                             ret
adjust_cursor_del endp

      ; TODO
      ; From LCD delete a character.
      ; Parameter :  None
delete_single_char proc
                             cmp    lcd_cursor, 0                      ; no character in LCD
                             je     finish_delete

                             dec    lcd_cursor                         ; point to which should be deleted
                             call   adjust_cursor_del

      start_delete:          
                             mov    al, ' '                            ; use 'space' to fill hole
                             call   write_data
      ; DDRAM default add 1, we need rejudege
      finish_delete:         
                             ret

delete_single_char endp

      ; TODO
      ; Only clear current imput information
      ; Parameter :  None
clear_current_input proc
      ; 两个步骤。1. 清除 buf， 2. 清除 屏幕
      ; 首先判断当前是输入的数字还是操作符
                             push   ax

                             cmp    digital_buffer_count, 0            ; compare the count to judge current input type
                             jne    cl_current_digital                 ; not 0, so current input is digital

      ; is 0, so current input is operator
      cl_current_operator:   


      ; 难点，怎么清除屏幕上的字符
      cl_current_digital:    
                             mov    ax, digital_buffer


                             pop    ax
                             ret
clear_current_input endp

      ; Judge whether current cursor position needs adjustment after display a new character.
      ; Parameter :  None
adjust_cursor_dis proc

                             push   ax

                             cmp    lcd_cursor, 16
                             je     adjust_l2_s

                             cmp    lcd_cursor, 32
                             je     adjust_l3_s

                             cmp    lcd_cursor, 48                     ; screen is full
                             je     adjust_l1_s                        ; Cicle fill character
    
      finish_adjust:         
                             pop    ax
                             ret

      adjust_l1_s:           
                             mov    al, LINE1_S                        ; point to line 1
                             call   write_cmd

                             jmp    finish_adjust

      adjust_l2_s:           
                             mov    al, LINE2_S                        ; point to line 2
                             call   write_cmd

                             jmp    finish_adjust

      adjust_l3_s:           
                             mov    al, LINE3_S                        ; point to line 3
                             call   write_cmd

                             jmp    finish_adjust

adjust_cursor_dis endp

      ; Trans single keyboard input to charactor and put it to LCD12864
      ; Parameter :
      ;              CL  --  Key id from keyboard
display_single_char proc
      ; 判断输入
                             push   ax

                             cmp    cl, 9
                             jbe    trans_digital_to_char              ;0-9
                             jmp    trans_op_id_to_char                ; else is operator

      start_display:         
                             mov    al, cl
                             call   write_data

                             inc    lcd_cursor                         ; mov cursor to next position
                             call   adjust_cursor_dis

      finish_write:          
                             pop    ax
                             ret

      trans_digital_to_char: 
                             add    cl, '0'
                             jmp    start_display

      trans_op_id_to_char:   
      trans_id_to_add:                                                 ; Judge add
                             cmp    cl, ADD_ID
                             jne    trans_id_to_sub
                           
                             mov    cl, '+'

                             jmp    start_display
      trans_id_to_sub:                                                 ; Judge sub
                             cmp    cl, SUB_ID
                             jne    trans_id_to_mul

                             mov    cl, '-'

                             jmp    start_display
      trans_id_to_mul:                                                 ; Judge mul
                             cmp    cl, MUL_ID
                             jne    trans_id_to_div

                             mov    cl, '*'

                             jmp    start_display
      trans_id_to_div:                                                 ; Judge div
                             cmp    cl, DIV_ID
                             jne    trans_id_to_lbrace
                             mov    cl, '/'

                             jmp    start_display
      trans_id_to_lbrace:    
                             cmp    cl, LBRACE
                             jne    trans_id_to_rbrace
                             mov    cl, '('

                             jmp    start_display
      trans_id_to_rbrace:    
                             mov    cl, ')'

                             jmp    start_display

display_single_char endp

      ; Print final result to LCD12864
      ; Parameter :  None
      ; Return :     None
display_final_result proc
                             push   ax
                             push   bx
                             push   cx
                             push   di

                             mov    ax, final_result
                             call   trans_to_char

                             mov    al, DIS_RES                        ; result need print to line 4
                             call   write_cmd

                             mov    bx, offset str_number_buffer
                             mov    cx, str_number_buffer_count
                             mov    di, cx
                             dec    di
      write_char:            
                             mov    ax, [bx+di]
                             call   write_data
                             dec    di

                             loop   write_char

                             mov    str_number_buffer_count, 0         ; reset

                             pop    di
                             pop    cx
                             pop    bx
                             pop    ax

                             ret
display_final_result endp

      ; Debounce funtion about keyboard input
      ; There are three stats here:
      ;     1. keyboard singal invalid, initial count and buffer, and return 20H(invalid input)
      ;     2. keyboard singal valid, but not achieve setting time, retain count and buffer, and return 20H(invalid input)
      ;     3. keyboard singal valid, and achieve setting time, retain count and buffer, and return truth input(valid input)
      ; When sys in the stat3, when the count finished, proc will set a new short cout. This is meaningful:
      ;     When user press one button don't move, sys should always reacte singal.
      ;     For realistic, sys first reaction coming so fast, but after this reaction, sys will 'sleep' for a middle time.
      ;     After this middle time, sys will rapid to reacte press.
      ;     For instructions, firstly, count is setted 88H, then sys will reacte when count decrease to 82H,
      ;     and next reaction will occur when count decrease to 0eh. When the count decrease to 00H, sys will
      ;     reset a very small count(0fh).
      ;     So:
      ;        1th reaction occurred at 82H, it pass 06H, is short
      ;        2th reaction occurred at 0eH, it pass 74H, is long
      ;            when count decrease to 00H, sys reset is as 0fH, so
      ;        3th reaction occurred at 0eH, it past 0fH (because reset as 0fH)
      ;            then repeat 3th until user dont press button.
      ; Parameter : None
      ; Return :
      ;             AL  --  Store the id of button
      ;             CL  --  Store the id of button
scan_debounce proc

                             call   scan_keyboard                      ; scan keyboard
                             mov    ah, al                             ; copy input to AH (protect current input)
                             mov    bl, shake_count                    ; press count
                             mov    bh, shake_key                      ; last input is stored in shake char
                             cmp    ah, bh                             ; compare current and last
                             mov    bh, ah                             ; update BH, now BH store current input
                             mov    ah, bl                             ; AL is updated as BL
                             jz     same_as_last                       ; current input equal last input, not shake
      not_same_as_last:                                                ; reset to state 1
                             mov    bl, 88h                            ; Judge as shake, fill invalid data
                             mov    ah, 88h
      ; instructions above all is judge shake
      same_as_last:                                                    ;current and last is same
                             dec    ah
                             cmp    ah, 82h
                             je     respond_press                      ; state 3
                             cmp    ah, 0eh                            ; 0000 1110
                             je     respond_press                      ; state 3
                             cmp    ah, 00h
                             je     reset_judge_count                  ; state 3
      ; not achieve setting time, return invalid
                             mov    ah, 20h                            ; set current input as invalid
                             dec    bl                                 ; count dec？
                             jmp    update_shake_buf
      reset_judge_count:                                               ; 计数器置零之后重新设置时间
                             mov    ah, 0fh                            ; 0000 1111, reset count number

      respond_press:         
      ; BL will store to shake buffer 0 (count)
      ; BH will sotre to shake buffer 1 (last input)
      ; AH will assign AL and CL (store current input)
      ; prepare for store to shake buffer
                             mov    bl, ah                             ; update count
                             mov    ah, bh                             ; assign current input to AH
      update_shake_buf:                                                ; judge finish, update shake buffer and trans key mapping
                             mov    shake_count, bl
                             mov    shake_key, bh                      ; value in BH is mapped to key_mapping list, BH is current input

                             mov    al, ah                             ; AH store the offset num about key_mapping list
                             mov    cl, ah

                             cmp    cl, 20h                            ; 20h is invalid key id, so directly terminate
                             jnc    scan_finish                        ; jnc: above and equal
      ; only reaction valid single
                             mov    bx, offset key_mapping
                             xlat                                      ; through input single get key mapping
                             mov    cl, al

      scan_finish:           ret
scan_debounce endp

      ; TODO: change position about 'rol' instruction
      ;       确定一下“关显示”是不是指的数码管
      ; Scan keyboard,
      ; Parameter :  None
      ; Return :
      ;              AL  --  Store the id(coding) about button(key)
scan_keyboard proc
                             mov    cl, 0feh                           ; 1111 1110, send to keyboard, determine which column is activated
                             mov    bx, 08h                            ; 0000 1000, How many time will scan when invoke
      ;但是键入只有5列，改成5也可以（测试后可以）

      lp0:                   mov    dx, outbit                         ; activate one column
                             mov    al, cl
                             out    dx, al

                             rol    cl, 01h                            ; change mark to activate next column()

                             mov    dx, inkey                          ; get keyboard row activate information
                             in     al, dx

                             not    al                                 ; info from keyboard is 1 invalid 0 valid, so here need NOT
                             and    al, 0fh                            ; keyboard only 4 row, so ONLY LOW 4 BIT VALID
                             cmp    al, 00h                            ; judge current row whether have position is activated
                             jnz    exist_activate                     ; process valid input
      ; invalid inpiut, scan next column
                             inc    bh                                 ; increase cnt
                             dec    bl                                 ; decrease cnt

                             cmp    bl, 00h                            ; judge loop finish or not
                             jnz    lp0                                ; loop not finish

      ; instructions below are after process input or no valid input to execute
      signal_invalid:        
                             mov    ah, 20h                            ; input invalid, mark as 20h
      process_signal:        

      ; instructions below may be is about “数码管” ？
                             mov    al, 00h                            ;al设置操作
                             mov    dx, outbit                         ;指向字位
                             out    dx, al                             ;关显示
      ; instructions above may be is about “数码管” ？

                             mov    al, ah                             ; put current scan result to al, 20h is invalid
                             ret

      ;---按键搜索入口
      ; al是键入编码，配合cl键扫可以计算出对应的按键
      exist_activate:        
                             cmp    al, 01h                            ; 0000 0001 judge row 0 whether activate
                             jnz    verify_row1                        ; not activate
                             mov    ah, 00h                            ; activate, make AH as 0000 0000
                             jmp    verify_finish

      verify_row1:           cmp    al, 02h                            ; 0000 0010 judge row 1 whether activate
                             jnz    verify_row2                        ; not activate
                             mov    ah, 08h                            ; activate, make AH as 0000 1000
                             jmp    verify_finish
      verify_row2:           cmp    al, 04h                            ; 0000 0100 judge row 2 whether activate
                             jnz    verify_row3                        ; not activate
                             mov    ah, 10h                            ; activate, make AH as 0000 1010
                             jmp    verify_finish
      verify_row3:           cmp    al, 08h                            ; 0000 1000 judge row 3 whether activate
                             jnz    signal_invalid                     ; not activate, all columu is invalid
                             mov    ah, 18h                            ; activate, make AH as 0001 1000
      verify_finish:                                                   ; signal have meaning
                             add    ah, bh                             ; BH store which column is activate
      ; in fact, AH determine Base coding, and BH determine Offset coding, merge AH and BH can get entirly coding
                             jmp    process_signal

scan_keyboard endp

      ; Initial LCD 12864
      ; Parameter :  None
initial proc

                             mov    al, 30h                            ;30h--基本指令操作
                             call   write_cmd

                             mov    al, 01h                            ; clear screen
                             call   write_cmd

                             call   delay_s                            ; wait

                             mov    al, 06h                            ;指定在资料写入或读取时，光标的移动方向
                             call   write_cmd
                             mov    al, 0ch                            ;开显示,关光标,不闪烁
                             call   write_cmd

                             mov    al, DDRAM                          ;写ddram，data display ram，指向开始
                             call   write_cmd

                             mov    dx, CS8255                         ;初始化 8255
                             mov    al, 89h                            ;1000 1001 方式 0，A口B口输出、C口输入
                             out    dx, al

                             ret
initial endp

      ; LCD 12864 : Write data to LCD
      ; Parameter :
      ;             AL  --  Which character you want to display
write_data proc near
                             push   dx
                             call   delay
                             mov    dx, wrdata
                             out    dx, al
                             pop    dx
                             ret
write_data endp

      ; LCD 12864 : Write command to LCD
      ; Parameter :
      ;             AL  --  Which command you want to display
write_cmd proc near
                             push   dx
                             call   delay
                             mov    dx, wricode
                             out    dx, al
                             pop    dx
                             ret
write_cmd endp

delay proc near
                             push   cx
                             mov    cx, 0F000h
                             loop   $
                             pop    cx
                             ret
delay endp

      ; Trans number from decimal to string expression.
      ; Parameter :
      ;              AX  --  Which num in decimal trans to charactor
      ; Return :
      ;              None, result is stored in str_number_buffer(stack)
trans_to_char proc
      ; protect context
                             push   bx
                             push   cx
                             push   dx
                             push   di

                             mov    str_number_buffer_count, 0         ; initial string buffer
                             mov    bx, offset str_number_buffer
                             xor    di, di

                             mov    cx, 10                             ;initial base

      get_next_char:         
    
                             xor    dx,dx                              ; 默认被除数是 32 位，因此 清空 dx
                             div    cx

                             add    dx, '0'
                             mov    [bx+di], dl                        ;因为这里都是小于 10 的数字，因此不会发生溢出， dx 中只有低八位有效
                             inc    di
                 
                             cmp    ax, 0                              ; 默认 ax 存放商， 因此直接判断即可
                             jne    get_next_char

                             mov    str_number_buffer_count, di

      ; restore context
                             pop    di
                             pop    dx
                             pop    cx
                             pop    bx

                             ret
trans_to_char endp


      ; parse postfix and calculate result
      ; Parameter :  None
      ; Return :
      ;              final_result  --  The final result of expression
calculate_postfix proc
      ; si - source - 指向 postfix
      ; di - target - 指向 stack
      ; initial
                             mov    bx, offset postfix_buffer
                             xor    si, si
                             xor    di, di                             ; Index of stack always point to next position

      judge_item_type:                                                 ; 检测 postfix 中当前的是 #（数字）还是 @（操作符）
                             cmp    si, postfix_buffer_count           ; Judge parse finish or not
                             je     cal_finish
                           
                             mov    ax, [bx+si]                        ;
                             add    si, 2                              ; Adjust index to point actually data

      judge_digital:         cmp    ax,'##'
                             jne    judge_operator

      is_digital:                                                      ; push digital to stack
                             mov    ax, [bx+si]                        ; Get actual data
                             add    si, 2                              ; Adjust index to next item, prepare for next parse
                             call   push_digital

                             jmp    judge_item_type
 
      judge_operator:        cmp    ax, '@@'
                             jne    cal_error
        
      is_operator:                                                     ; judge operator tupe and execute
                             mov    ax, [bx+si]                        ; Get actual operator
                             add    si, 2                              ; Adjust index to next item

                             call   judge_operator_type
  
                             jmp    judge_item_type
      cal_finish:            
      ; Calculate is finished, data in stack top is the result about express
                             call   pop_digital

                             mov    final_result, ax
                          
                             call   display_finish

                             ret
calculate_postfix endp

      ; Judge operator type and caclulate result.
      ; Parameter :
      ;              AX  --  input from keyboard
      ; Return :
      ;              None
judge_operator_type proc
      ; 计算的步骤是从 stack 中 pop 两个数，然后计算，最后push结果进栈
      judge_op_add:                                                    ; Judge add
                             cmp    ax, 10
                             jne    judge_op_sub
                           
                             call   execute_add

                             jmp    execute_finish
      judge_op_sub:                                                    ; Judge sub
                             cmp    ax, 11
                             jne    judge_op_mul

                             call   execute_sub

                             jmp    execute_finish
      judge_op_mul:                                                    ; Judge mul
                             cmp    ax, 12
                             jne    judge_op_div

                             call   execute_mul

                             jmp    execute_finish
      judge_op_div:                                                    ; Judge div
                             cmp    ax, 13
                             jne    cal_error

                             call   execute_div

                             jmp    execute_finish

      cal_error:             
                             call   display_cal_error
      ;                        jmp    end_start

      execute_finish:        ret
judge_operator_type endp

      ; Execute add operation
      ; Parameter :  None
      ;
execute_add proc

      ; protect context
                             push   ax
                             push   dx
                           
                             call   pop_digital
                             mov    dx, ax                             ; Store first data from stack
                             call   pop_digital

                             add    ax, dx

                             call   push_digital
      ; restore context
                             pop    dx
                             pop    ax

                             ret
execute_add endp

      ; Execute sub operation
      ; Parameter :  None
      ;
execute_sub proc

      ; protect context
                             push   ax
                             push   dx
                                                      
                             call   pop_digital
                             mov    dx, ax                             ; Store first data from stack
                             call   pop_digital

                             sub    ax, dx

                             call   push_digital
      ; restore context
                             pop    dx
                             pop    ax
                             ret
execute_sub endp

      ; Execute mul operation
      ; Parameter :  None
      ;
execute_mul proc
      ; protect context
                             push   ax
                             push   dx

                             call   pop_digital
                             mov    dx, ax                             ; Store first data from stack
                             call   pop_digital

                             mul    dx                                 ; Result default store in AX

                             call   push_digital
      ; restore context
                             pop    dx
                             pop    ax
                             ret
execute_mul endp

      ; Execute div operation
      ; Parameter :  None
      ;
execute_div proc
      ; protect context
                             push   ax
                             push   dx
                             push   cx

                             call   pop_digital
                             mov    cx, ax                             ; Store first data from stack
                        
                             call   pop_digital                        ; return to AX

                             xor    dx, dx                             ; div instructor is diiferent with other, so we need empty DX

                             div    cx                                 ; Result default store in AX

                             call   push_digital
      ; restore context
                             pop    cx
                             pop    dx
                             pop    ax

                             ret
execute_div endp

      ; Get calculat stack top data and adjust DI.
      ; Parameter :
      ;              DI -- Store destination data offset address, point to an empty position
      ; Return :
      ;              AX -- Data in stack top
pop_digital proc
                             push   bx

                             mov    bx, offset calculate_stack
                        
                             sub    di, 2                              ; Adjust index to next position
                        
                             mov    ax, [bx+di]                        ; DI poitn a empty position, so we need -2 to get data in stack top


                             pop    bx

                             ret
pop_digital endp

      ; Push digital to calculate stack.
      ; Parameter :
      ;             AX -- Which data you want to push to stack
      ;             DI -- Store destination data offset address, point to an empty position
push_digital proc

                             push   bx                                 ; protect offset address

                             mov    bx, offset calculate_stack
                             mov    [bx+di], ax
                             add    di, 2                              ; Adjust index to point next position

                             pop    bx                                 ; restore offset address

                             ret
push_digital endp

      ; Empty operator stack, add all operator to postfix.
      ; Parameter : None
empty_op_stk proc

      ; protect context
                             push   bx
                             push   cx
                             push   di

                             cmp    operator_stack_index, 0
                             je     end_ept_stk

                             mov    bx, offset operator_stack
                             mov    cl, operator_stack_index
                             mov    di, cx
      start_empty_op_stk:                                              ;清空符号栈
                             dec    di                                 ;因为默认指向下一个位置，需要-1
                             mov    dx, [bx+di]
                      
                             call   store_operator

                             cmp    di, 0                              ; 判断一下有没有清空
                             jne    start_empty_op_stk

                             mov    operator_stack_index, 0            ;重置栈指针

      end_ept_stk:           
      ; restore context
                             pop    di
                             pop    cx
                             pop    bx

                             ret
empty_op_stk endp


      ; Update digital buffer by input.
      ; Parameter :
      ;             AX  --  Input information. Is number not character. ONLY low 8 bit valid
update_number proc
                             push   bx

                             mov    bx, digital_buffer

                             push   ax                                 ;保护输入
                             push   dx

                             mov    ax, 10
                             mul    bx                                 ; AX 存放低16位 DX 存放高16位
                           
                             mov    bx, ax                             ; 这里先只处理 AX，

                             pop    dx
                             pop    ax                                 ; al 中存着输入，保护一下

                             and    ax, 00ffh                          ; 只保留低8位
                             add    bx, ax

                             mov    digital_buffer, bx

                             inc    digital_buffer_count               ;用于判断输入是否合法

                             pop    bx
                             ret
update_number endp

      ; Process current input operator.Translate expression to postfix.
      ; Parameter :
      ;             AX -- Current input information. ONLY low 8 bit valid.
process_operator proc
      ; 判断当前操作符该如何处置
      ; protect context
                             push   bx
                             push   cx
                             push   di
                             push   dx

                             push   ax                                 ; 保护原始输入
      ; 栈空，直接入栈
                             cmp    operator_stack_index, 0
                             je     push_operator
      ; 栈非空，需要判断优先级
                             mov    bx, offset operator_stack
                             mov    cl, operator_stack_index
                             mov    di, cx

      ;判断是不是左括号，左括号直接进栈，不需要弹出任何东西
                             cmp    al, LBRACE
                             je     push_operator

      ; 先判断要入栈的是不是右括号 )，如果是的话开始弹出，直到左括号，并且无符号入栈
                             cmp    al, RBRACE
                             jnz    judge_stk_top_priority
      ; 是右括号，开始弹出
      find_left_brace:       
                             dec    di
                             dec    operator_stack_index

                             cmp    byte ptr [bx+di], LBRACE           ; 根据键盘映射 15 表示 （
                             je     pre_process_finish                 ; 停止弹出，并且这个不用存储到 postfix

                             mov    dx, [bx+di]
                             call   store_operator

                             jmp    find_left_brace

      judge_stk_top_priority:                                          ; 不是右括号，判断优先级
                             dec    di                                 ;因为默认指向下一个空位置，所以这里要-1，同时可以起到pop的作用

      ; 需要特判一下是不是 左括号 (
                             cmp    byte ptr [bx+di], LBRACE           ; 根据键盘映射 15 表示 （
                             je     push_operator                      ; '(' has lowest priority in stack，so we can push
      ; 不是括号

      ;判断优先级，al 和 [bx+di]，当前优先级大于的时候进栈
                             mov    ah, [bx+di]
                             and    ax, 0606h                          ; 现在 ah 是 栈顶， al 是待入

                             cmp    al, ah
                             ja     push_operator                      ; al>ah, 说明优先级高，可以入栈
      ;说明优先级不行，要弹出操作符，直到栈空或者小于
      pop_operator:          
      ;需要把 栈顶 的操作符弹到 postfix 中
                             mov    dx, [bx+di]

                             call   store_operator

                             dec    operator_stack_index

                             cmp    di, 0
                             jne    judge_stk_top_priority             ; 如果还有就返回，重新判断

      ; 否则没有了，顺序执行到下面直接进栈
                
      push_operator:         
                             pop    ax                                 ; 取回现场中保存的值

                             mov    bx, offset operator_stack
                             mov    cl, operator_stack_index
                             mov    di, cx
                             and    ax, 00ffh
                             mov    [bx+di], al
                             inc    operator_stack_index
      process_finish:        
      ; restore context
                             pop    dx
                             pop    di
                             pop    cx
                             pop    bx

                             ret
      pre_process_finish:    
                             pop    ax
                             jmp    process_finish

process_operator endp


      ; Store digital from buffer to postfix and initial digital buffer.
      ; Parameter:  None
store_number proc

      ; protect context
                             push   bx
                             push   cx
                             push   dx
                             push   di
      ; judge is empty or not
                             cmp    digital_buffer_count, 0
                             je     store_finish
      ;store digital to context
                             mov    bx, offset postfix_buffer
                             mov    cx, postfix_buffer_count
                             mov    di, cx
                             mov    [bx+di], '##'                      ;数字的分隔符
                             mov    dx, digital_buffer
                             mov    [bx+di+2], dx
                             add    postfix_buffer_count, 4
                           
      store_finish:          
      ;restore context
                             pop    di
                             pop    dx
                             pop    cx
                             pop    bx
      ; initial digital buffer
                             mov    digital_buffer, 0
                             mov    digital_buffer_count, 0

                             ret
store_number endp

      ; Store operator from DX to postfix.
      ; Parameter :
      ;             DX  --  Which operator you want to store. ONLY low 8 bit valid
store_operator proc

                             push   bx
                             push   cx
                             push   di

                             and    dx, 00ffh                          ; 操作符只占一个 Byte，因此清空高位
                             mov    bx, offset postfix_buffer
                             mov    cx, postfix_buffer_count
                             mov    di, cx
                             mov    [bx+di], '@@'                      ; operator 的分隔符
                             mov    [bx+di+2], dx
                             add    postfix_buffer_count, 4
                           
                             pop    di
                             pop    cx
                             pop    bx

                             ret
store_operator endp


      ; Display error.
display_error proc
                             push   dx
                             push   ax

                             mov    dx, offset input_error_prompt
                             mov    ah, 09h
                             int    21h

                             pop    ax
                             pop    dx
            
                             ret
display_error endp

      ; Display calculate error.
display_cal_error proc
                             push   dx
                             push   ax

                             mov    dx, offset cal_error_prompt
                             mov    ah, 09h
                             int    21h

                             pop    ax
                             pop    dx
            
                             ret
display_cal_error endp


      ; tempoary procedure, display finish infomation
display_finish proc
                             push   dx
                             push   ax

                             call   next_line
            
                             mov    dx, offset cal_finish_prompt
                             mov    ah, 09h
                             int    21h

                             call   next_line

                             pop    ax
                             pop    dx
            
                             ret
display_finish endp

      ; display next line
next_line proc

                             push   dx
                             push   ax

                             mov    dl, 0dh
                             mov    ah, 02h
                             int    21h

                             mov    dl, 0ah
                             int    21h
                           
                             pop    dx
                             pop    ax

                             ret
next_line endp

code ends
        end start

"""Render the actual DCIM board-top relationships as one 16:9 slide.
Usage: python3 render_top_relationship.py --font /path/to/CJK-font.otf
SVG embeds glyph paths so presentation computers need no extra font.
"""
from pathlib import Path
import argparse
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

p = argparse.ArgumentParser()
p.add_argument('--font', required=True)
args = p.parse_args()
font_manager.fontManager.addfont(args.font)
plt.rcParams['font.family'] = font_manager.FontProperties(fname=args.font).get_name()
plt.rcParams['svg.fonttype'] = 'path'
fig, ax = plt.subplots(figsize=(19.2, 10.8), dpi=100)
fig.subplots_adjust(0, 0, 1, 1)
ax.set(xlim=(0, 1920), ylim=(1080, 0))
ax.axis('off')
ink, blue, teal, amber = '#17324d', '#2868b2', '#087f82', '#b16d10'

def text(x, y, s, size=16, color=ink, align='center'):
    ax.text(x, y, s, fontsize=size, color=color, ha=align, va='center', linespacing=1.5)

def box(x, y, w, h, title, body, color=blue, size=16):
    ax.add_patch(FancyBboxPatch((x,y),w,h,boxstyle='round,pad=0,rounding_size=15',
        edgecolor=color, facecolor='#f1f6fb', linewidth=2))
    text(x+w/2,y+32,title,19,color)
    text(x+w/2,y+h/2+22,body,size)

def arrow(points, color=blue, dashed=False):
    style='--' if dashed else '-'
    for a,b in zip(points[:-2],points[1:-1]):
        ax.plot([a[0],b[0]],[a[1],b[1]],color=color,lw=2,ls=style)
    ax.add_patch(FancyArrowPatch(points[-2],points[-1],arrowstyle='-|>',
        mutation_scale=17,lw=2,color=color,linestyle=style))

text(65,48,'DCIM 板級架構｜誰下命令？誰控制腳位？誰提供時脈？',29,align='left')
text(65,99,'dcim_master_chip_top：同一個 50 MHz 時脈域，無 CDC；模組連接依目前 RTL 繪製',17,align='left')
ax.add_patch(FancyBboxPatch((30,140),1860,770,boxstyle='round,pad=0,rounding_size=18',
    edgecolor='#c9d5e2',facecolor='white',linewidth=1.5,zorder=-1))

box(65,170,630,195,'u_clock_gen｜提供時脈',
    'dcim_clock_gen_125_to_50\n板上 125 MHz → IBUF → MMCM → BUFG → 50 MHz\nMMCM：125 × 8 ÷ 20 = 50 MHz；另有回授 BUFG',teal,16)
box(805,170,430,195,'Top 的 reset 邏輯',
    'reset_button OR !clock_locked\n非同步進入 reset\n經 2 級 50 MHz FF 釋放 reset',amber,17)
box(1370,170,470,195,'LED｜對外觀察',
    'LED0 = clock_locked\nLED1 = test_busy\nLED2 = test_pass　 LED3 = test_fail',blue,17)
arrow([(695,250),(805,250)],teal)
text(750,221,'locked',13,teal)
text(1605,389,'locked 來自 clock_gen；測試狀態來自 self_test',13)

# Shared distribution buses: timing/control paths are distinct from data.
arrow([(190,365),(190,425),(1750,425)],teal,True)
text(1030,410,'clk_50m：三個功能模組共用',14,teal)
for x in (230,900,1570):
    arrow([(x,425),(x,520)],teal,True)
arrow([(1090,365),(1090,470),(1790,470)],amber,True)
ax.plot([270,1090],[470,470],color=amber,lw=2,ls='--')
text(1370,457,'reset_50m',13,amber)
for x in (270,940):
    arrow([(x,470),(x,520)],amber,True)
text(1732,495,'Chip reset 由 master 輸出',12,amber)

box(65,520,460,330,'① u_self_test｜測試指揮者',
    'dcim_board_self_test\n\n決定：位址、權重、activation、操作順序\n等待 master_done，核對結果\n\n寫整陣列 → 逐筆讀回 → 一次 A8W8\n完成後保持 PASS／FAIL',blue,17)
box(735,520,460,330,'② u_pin_master｜腳位時序控制',
    'dcim_pin_master\n\nIDLE 接受 start，鎖存命令\n分拍執行 write／read／burst／CIM\n\n產生 chip 控制腳位與 din\n收齊序列 bits，再回報 done／結果',blue,17)
box(1405,520,435,330,'③ u_chip｜實際執行',
    'dcim_chip_pin_top\n\n128×128 cell 數位模型\n儲存權重／SRAM 讀取／CIM\n\n序列輸出 sume、sumo\n不是實體 FeFET 電性模型',blue,17)

arrow([(525,600),(735,600)])
text(630,561,'命令 →',15,blue)
text(630,641,'start／operation\n位址／weight／activation',12,blue)
arrow([(735,760),(525,760)])
text(630,720,'← 狀態／結果',15,blue)
text(630,805,'busy／done／valid／error\nread_data／even／odd',12,blue)

arrow([(1195,600),(1405,600)])
text(1300,561,'腳位 →',15,blue)
text(1300,646,'mode／位址／din\nwrite／sense／output_en\nclk_en／reset 等',12,blue)
arrow([(1405,760),(1195,760)])
text(1300,720,'← 序列結果',15,blue)
text(1300,800,'sume／sumo\n每拍各接收 1 bit',13,blue)

text(940,883,'Burst 特例：master 提出下一筆位址；self_test 回傳 weight，valid && ready 才接受。',15)
text(65,951,'一次自我測試：2048-byte burst write → 2048 次 SRAM read 比對 → Group0 / Pair0 A8W8 → PASS 或 FAIL',19,align='left')
text(65,995,'核心分工：self_test 決定「做什麼」；pin_master 決定「每拍腳位怎麼動」；clock_gen 提供共同時間基準。',18,align='left')
text(65,1042,'圖例：藍色實線＝命令／資料　綠色虛線＝50 MHz 時脈　橘色虛線＝reset；LED 方塊以文字標示來源。',14,align='left')
out=Path(__file__).resolve().parent
for ext in ('png','svg'):
    fig.savefig(out/f'dcim_top_relationship_16x9.{ext}',dpi=100,facecolor='white')
plt.close(fig)

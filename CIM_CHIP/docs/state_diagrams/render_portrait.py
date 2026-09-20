"""Portrait companion figures; run with --font /path/to/CJK-font.otf."""
from pathlib import Path
import argparse
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib.patches import FancyBboxPatch, Polygon, FancyArrowPatch

p=argparse.ArgumentParser(); p.add_argument('--font',required=True); args=p.parse_args()
font_manager.fontManager.addfont(args.font)
plt.rcParams['font.family']=font_manager.FontProperties(fname=args.font).get_name()
plt.rcParams['svg.fonttype']='path'
OUT=Path(__file__).resolve().parent
INK='#18324b'; BLUE='#2469a0'; TEAL='#117f79'

def txt(x,y,s,size=15,color=INK):
    ax.text(x,y,s,ha='center',va='center',fontsize=size,color=color,linespacing=1.45)

def box(y,name,body,h=145,done=False):
    c=TEAL if done else BLUE
    ax.add_patch(FancyBboxPatch((290,y),500,h,boxstyle='round,pad=0,rounding_size=14',
                              ec=c,fc='#edf8f5' if done else '#eef5fb',lw=2))
    txt(540,y+30,name,18,c)
    txt(540,y+h/2+22,body,14)

def diamond(y,label):
    ax.add_patch(Polygon([(540,y),(740,y+65),(540,y+130),(340,y+65)],closed=True,
                         fc='#fff5e5',ec='#b97618',lw=2))
    txt(540,y+65,label,14)

def edge(points,label=None,pos=None):
    for a,b in zip(points[:-2],points[1:-1]):
        ax.plot([a[0],b[0]],[a[1],b[1]],color=INK,lw=1.8)
    ax.add_patch(FancyArrowPatch(points[-2],points[-1],arrowstyle='-|>',mutation_scale=16,lw=1.8,color=INK))
    if label:
        ax.text(*pos,label,ha='center',va='center',fontsize=13,color=INK,
                bbox=dict(facecolor='white',edgecolor='none',pad=3),linespacing=1.45)

def down(a,b,label='無條件'):
    edge([(540,a),(540,b)],label,(650,(a+b)/2))

def start(title,sub,metric):
    global fig,ax
    fig,ax=plt.subplots(figsize=(10.8,19.2),dpi=100)
    fig.subplots_adjust(0,0,1,1); ax.set(xlim=(0,1080),ylim=(1920,0)); ax.axis('off')
    fig.patch.set_facecolor('white'); ax.axhspan(0,12,color=BLUE)
    txt(540,70,title,28); txt(540,125,sub,15); txt(540,177,metric,20,TEAL)
    txt(540,1830,'圓角框＝RTL 狀態；菱形＝組合判斷，不增加 clock。',14)
    txt(540,1870,'T0＝接受 start 的上升緣；全域 rst=1 可非同步返回 IDLE。',13)

def finish(name):
    for ext in ('png','svg'): fig.savefig(OUT/f'{name}_state_9x16.{ext}',dpi=100,facecolor='white')
    plt.close(fig)

start('SRAM READ｜讀取狀態圖','operation = 1｜省略每筆 Read Reset','9 clocks · 180 ns @ 50 MHz')
box(260,'ST_IDLE','等待 start；read_bit_count = 7')
txt(540,235,'start=0：保持 IDLE',12)
down(405,510,'start=1 且 op=1')
box(510,'ST_READ_CAPTURE','1 clock：wl_en / sense_en / pre_en = 1\nsel_next = 1；覆寫完整 W8',170)
down(680,790)
box(790,'ST_READ_SHIFT','每次 1 clock，共 8 次\n接收 sumo → data[read_bit_count]\nsense_en = 0',175)
down(965,1040,'')
diamond(1040,'read_bit_count == 0 ?')
down(1170,1290,'是')
box(1290,'ST_DONE','done=1；result_valid=1',done=True)
edge([(740,1105),(960,1105),(960,877),(790,877)],'否：減 1\n繼續接收',(924,1000))
edge([(290,1360),(140,1360),(140,332),(290,332)],'DONE 1 clock\n後回 IDLE',(140,720))
txt(540,1540,'T1：載入後 bit[7] 立即可見\nT2～T9：Master 接收 bit[7:0]\nT9：done=1',20,TEAL)
txt(540,1690,'Capture 完整覆寫，不需先清零 Serializer。\nMaster 接收的是上升緣前的 sumo；\n上升緣後 Serializer 已移到下一 bit。',16)
finish('sram_read')

start('SRAM WRITE｜寫入狀態圖','operation = 0｜單筆 W8 Write，非 Burst','3 clocks · 60 ns @ 50 MHz')
box(260,'ST_IDLE','等待 start；暫存位址與 W8')
txt(540,235,'start=0：保持 IDLE',12)
down(405,495,'start=1 且 op=0')
box(495,'ST_WRITE_LOAD_HIGH','1 clock：clk_en=1；sel_next=0\ndin = weight[7:4]',165)
down(660,750)
box(750,'ST_WRITE_LOAD_LOW','1 clock：clk_en=1；sel_next=0\ndin = weight[3:0]',165)
down(915,1005)
box(1005,'ST_WRITE_CELL','1 clock：wl_en / write_en / sel_next = 1\nclk_en=0；選定 Cells 寫入 W8',165)
down(1170,1260)
box(1260,'ST_DONE','done=1；result_valid=0',done=True)
edge([(290,1330),(140,1330),(140,332),(290,332)],'DONE 1 clock\n後回 IDLE',(140,810))
txt(540,1510,'範例 W8 = A5\nT1：stage0 ← A\nT2：stage1 ← A；stage0 ← 5\nT3：Row／Pair 對應的 8 個 Cells ← A5',19,TEAL)
txt(540,1690,'Even = Weight[7:4]；Odd = Weight[3:0]\nmode_sel / sense_en / output_en = 0\n下一筆命令最早於 T5 接受。',16)
finish('sram_write')

start('CIM｜運算狀態圖','operation = 2｜Even／Odd 平行運作','91 clocks · 1.82 µs @ 50 MHz')
box(235,'ST_IDLE','start=0：保持；接受時 stage=7、plane=7',105)
down(340,385,'start=1 且 op=2')
box(385,'ST_CIM_RESET','1 clock：reset1=1；reset2=1',105)
down(490,535)
box(535,'ST_CIM_LOAD','每次 1 clock，共 8 次；clk_en=1\nsel_next=0；din 載入目前 plane 的 4 bits',135)
down(670,710,'')
diamond(710,'stage_count == 0 ?')
down(840,885,'是；stage ← 7')
box(885,'ST_CIM_SAMPLE','1 clock：sel_next=1；output_en=1\nACC ← (ACC << 1) + partial_sum',135)
down(1020,1060,'')
diamond(1060,'plane_count == 0 ?')
down(1190,1235,'是；輸出計數 ← 17')
box(1235,'ST_RESULT_CAPTURE','每次 1 clock，共 18 次\n平行接收 sume／sumo；sel_next=1',135)
down(1370,1410,'')
diamond(1410,'result_bit_count == 0 ?')
down(1540,1585,'是')
box(1585,'ST_DONE','done=1；result_valid=1',105,True)
edge([(740,775),(890,775),(890,600),(790,600)],'否：stage 減 1',(910,698))
edge([(740,1125),(1010,1125),(1010,557),(790,557)],'否：plane 減 1',(938,1040))
edge([(740,1475),(935,1475),(935,1302),(790,1302)],'否：輸出計數減 1',(925,1395))
edge([(290,1637),(110,1637),(110,287),(290,287)],'DONE 後\n回 IDLE',(110,965))
txt(540,1740,'1 + 8 × (8 + 1) + 18 = 91 clocks',19,TEAL)
txt(540,1785,'CIM 執行狀態 mode_sel=1；A4 前 4 planes 送 0，A8 送 A[7:0]。',12)
finish('cim')
print('Created 3 portrait PNGs and 3 SVGs (1080 x 1920).')

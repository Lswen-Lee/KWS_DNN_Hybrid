"""Render slide-sized RTL state diagrams. Requires matplotlib and a CJK font."""
from pathlib import Path
import argparse
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Polygon, FancyArrowPatch
from matplotlib import font_manager

parser = argparse.ArgumentParser()
parser.add_argument('--font', required=True)
args = parser.parse_args()
font_manager.fontManager.addfont(args.font)
plt.rcParams['font.family'] = font_manager.FontProperties(fname=args.font).get_name()
plt.rcParams['svg.fonttype'] = 'path'
OUT = Path(__file__).resolve().parent
INK, BLUE, TEAL, ORANGE = '#18324b', '#2469a0', '#117f79', '#b97618'

def text(x, y, s, size=16, color=INK, ha='center', weight='normal'):
    ax.text(x,y,s,fontsize=size,color=color,ha=ha,va='center',weight=weight,linespacing=1.5)

def box(x,y,w,h,title,body='',color=BLUE):
    ax.add_patch(FancyBboxPatch((x,y),w,h,boxstyle='round,pad=0,rounding_size=14',
                              linewidth=2,edgecolor=color,facecolor='#eef5fb' if color==BLUE else '#edf8f5'))
    text(x+w/2,y+35,title,16,color,weight='bold')
    if body: text(x+w/2,y+h/2+22,body,14)

def diamond(x,y,w,h,label):
    ax.add_patch(Polygon([(x+w/2,y),(x+w,y+h/2),(x+w/2,y+h),(x,y+h/2)],
                         closed=True,fc='#fff5e5',ec=ORANGE,lw=2))
    text(x+w/2,y+h/2,label,14)

def edge(points,label=None,labelpos=None):
    for a,b in zip(points[:-2],points[1:-1]):
        ax.plot([a[0],b[0]],[a[1],b[1]],color=INK,lw=1.8)
    ax.add_patch(FancyArrowPatch(points[-2],points[-1],arrowstyle='-|>',mutation_scale=15,lw=1.8,color=INK))
    if label: text(*labelpos,label,13)

def base(title,subtitle,metric):
    global fig,ax
    fig,ax=plt.subplots(figsize=(19.2,10.8),dpi=100)
    fig.subplots_adjust(0,0,1,1)
    ax.set(xlim=(0,1920),ylim=(1080,0)); ax.axis('off')
    fig.patch.set_facecolor('white')
    ax.add_patch(FancyBboxPatch((0,0),1920,12,boxstyle='square,pad=0',fc=BLUE,ec='none'))
    text(70,72,title,29,ha='left',weight='bold')
    text(70,130,subtitle,16,ha='left')
    text(1845,76,metric,20,TEAL,ha='right',weight='bold')
    text(70,1015,'圖例：圓角框＝RTL 狀態　｜　菱形＝組合判斷（不增加 clock）　｜　箭頭＝下一個上升緣的轉移',14,ha='left')
    text(70,1050,'時序基準：T0 為 IDLE 接受 start 的上升緣；全域 rst=1 可非同步返回 IDLE。',13,ha='left')

def save(name):
    for ext in ('png','svg'):
        fig.savefig(OUT/f'{name}.{ext}',dpi=100,facecolor='white')
    plt.close(fig)

base('SRAM READ｜讀取狀態圖','operation = 1　｜　每筆讀取直接 Capture；不再先啟用 reset2','9 clocks · 180 ns @ 50 MHz')
box(65,390,210,190,'ST_IDLE','等待 start\n接受時 bit_count=7')
box(390,390,315,190,'ST_READ_CAPTURE','1 clock\nwl_en / sense_en / pre_en = 1\nsel_next = 1；完整載入 W8')
box(810,390,290,190,'ST_READ_SHIFT','每次 1 clock，共 8 次\n接收 sumo → data[bit_count]\nsense_en = 0')
diamond(1180,395,260,180,'read_bit_count\n== 0 ?')
box(1540,390,290,190,'ST_DONE','done = 1\nresult_valid = 1',TEAL)
edge([(275,485),(390,485)],'start=1 且 op=1',(332,350))
edge([(705,485),(810,485)],'無條件',(756,460))
edge([(1100,485),(1180,485)])
edge([(1440,485),(1540,485)],'是',(1490,460))
edge([(1310,575),(1310,670),(955,670),(955,580)],'否：bit_count 減 1，繼續接收',(1100,705))
edge([(1685,390),(1685,255),(170,255),(170,390)],'無條件：DONE 1 clock 後回 IDLE',(955,230))
text(170,620,'start=0：保持 IDLE',13)
text(950,815,'T1：載入後立即顯示 bit[7]　→　T2～T9：Master 接收 bit[7:0]　→　T9：done=1',19,TEAL)
text(950,877,'Capture 覆寫完整 8 bits；Master 在上升緣接收的是 Serializer 移位前的 sumo。',16)
text(950,922,'READ_SHIFT 期間 wl_en / sense_en / pre_en / clk_en / sel_next / output_en 均為 0。',14)
save('sram_read_state_16x9')

base('SRAM WRITE｜單筆寫入狀態圖','operation = 0　｜　W8 = {Even 高 4 bits, Odd 低 4 bits}　｜　此圖為單筆 Write，非 Burst','3 clocks · 60 ns @ 50 MHz')
box(65,390,205,210,'ST_IDLE','等待 start\n暫存位址與 W8')
box(365,390,325,210,'ST_WRITE_LOAD_HIGH','1 clock\nclk_en=1；sel_next=0\ndin = weight[7:4]')
box(785,390,325,210,'ST_WRITE_LOAD_LOW','1 clock\nclk_en=1；sel_next=0\ndin = weight[3:0]')
box(1205,390,325,210,'ST_WRITE_CELL','1 clock\nwl_en / write_en / sel_next = 1\nclk_en = 0')
box(1625,390,225,210,'ST_DONE','done = 1\nresult_valid = 0',TEAL)
edge([(270,495),(365,495)],'start=1 且 op=0',(318,350))
for a,b in [(690,785),(1110,1205),(1530,1625)]: edge([(a,495),(b,495)],'無條件',((a+b)/2,465))
edge([(1737,390),(1737,255),(167,255),(167,390)],'無條件：DONE 1 clock 後回 IDLE',(950,230))
text(167,645,'start=0：保持 IDLE',13)
text(527,660,'T1：stage0 ← High',15,TEAL)
text(947,660,'T2：stage1 ← High；stage0 ← Low',14,TEAL)
text(1367,660,'T3：8 個 Cells 寫入 W8',15,TEAL)
text(950,795,'範例 W8 = A5：din 先送 A，再送 5，最後一個上升緣將 A5 寫入選定 Row／Pair。',19,TEAL)
text(950,857,'所有狀態 mode_sel=0；sense_en=0；output_en=0。位址在整筆命令期間保持不變。',16)
text(950,912,'接受下一筆命令最早為 T5；3-clock 延遲不包含 DONE／IDLE 的命令交接。',15)
save('sram_write_state_16x9')

base('CIM｜運算與序列輸出狀態圖','operation = 2　｜　A4／A8 都處理 8 個 planes　｜　Even、Odd 兩路平行','91 clocks · 1.82 µs @ 50 MHz')
box(50,260,200,180,'ST_IDLE','接受命令\nstage=7；plane=7')
box(330,260,245,180,'ST_CIM_RESET','1 clock\nmode_sel=1\nreset1=1；reset2=1')
box(665,260,270,180,'ST_CIM_LOAD','每次 1 clock，共 8 次\nclk_en=1；sel_next=0\ndin：目前 plane 的 4 bits')
diamond(1015,260,240,180,'stage_count\n== 0 ?')
box(1360,260,350,180,'ST_CIM_SAMPLE','每次 1 clock\nsel_next=1；output_en=1\nACC ← (ACC << 1) + partial_sum')
edge([(250,350),(330,350)],'start=1 / op=2',(288,230))
edge([(575,350),(665,350)],'無條件',(620,325))
edge([(935,350),(1015,350)])
edge([(1255,350),(1360,350)],'是；stage 重設為 7',(1307,225))
edge([(1135,260),(1135,190),(800,190),(800,260)],'否：stage 減 1',(963,169))
diamond(1415,565,240,180,'plane_count\n== 0 ?')
edge([(1535,440),(1535,565)])
edge([(1655,655),(1800,655),(1800,495),(800,495),(800,440)],'否：plane 減 1；載入下一個 plane',(1140,520))
box(1005,565,320,180,'ST_RESULT_CAPTURE','每次 1 clock，共 18 次\n接收 sume / sumo\nresult_bit_count：17 → 0')
edge([(1415,655),(1325,655)],'是',(1370,625))
diamond(660,565,250,180,'result_bit_count\n== 0 ?')
edge([(1005,655),(910,655)])
box(285,565,275,180,'ST_DONE','done=1\nresult_valid=1',TEAL)
edge([(660,655),(560,655)],'是',(610,625))
edge([(785,745),(785,805),(1165,805),(1165,745)],'否：result_bit_count 減 1',(975,837))
edge([(285,655),(150,655),(150,440)],'無條件：回 IDLE',(148,705))
text(150,472,'start=0：保持',12)
text(1535,792,'最後一次 Sample 同緣載入輸出\nbit[17] 立即可見',14,TEAL)
text(950,900,'1 Reset + 8 × (8 Load + 1 Sample) + 18 Receive = 91 clocks',20,TEAL)
text(950,950,'A4：0,0,0,0,A[3:0]；A8：A[7:0]，皆 MSB-first。CIM 各執行狀態 mode_sel=1。',15)
save('cim_state_16x9')
print('Created three PNG files (1920 x 1080) and three SVG files in', OUT)

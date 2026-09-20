"""Square 128x32 memory overview and a 16:9 presentation slide."""
from pathlib import Path
import csv
import argparse
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib.colors import ListedColormap
from matplotlib.patches import Rectangle, FancyBboxPatch

p=argparse.ArgumentParser(); p.add_argument('--font',required=True)
p.add_argument('--lsb-layout',action='store_true',help='Save a separate A,A[0],A[1],A[2],A[3],Row figure.')
args=p.parse_args()
font_manager.fontManager.addfont(args.font)
plt.rcParams['font.family']=font_manager.FontProperties(fname=args.font).get_name()
plt.rcParams['svg.fonttype']='path'
out=Path(__file__).resolve().parent
with (out/'before_cmd62_128x32.csv').open() as f:
    rows=list(csv.reader(f))[1:]
mem=np.array([[int(x,16) for x in r[1:]] for r in rows])
assert mem.shape==(128,32)
tags=np.zeros((128,32),dtype=int)
tags[45,18:20]=1; tags[46,20:22]=1; tags[47,22:24]=1
tags[40,28:32]=2; tags[41,:]=2; tags[42,:4]=2
tags[:32,4:6]=3
palette=['#fafcfe','#ffe0ac','#cddffc','#8adac1']
ink='#18324b'; teal='#14765e'

def square(fig,rect,values=False):
    ax=fig.add_axes(rect)
    ax.imshow(tags,aspect='auto',interpolation='nearest',cmap=ListedColormap(palette),vmin=0,vmax=3)
    ax.set_xlim(-.5,31.5); ax.set_ylim(127.5,-.5)
    ticks=[0,4,5,15,18,19,20,21,22,23,28,31]
    ax.set_xticks(ticks,[str(i) for i in ticks],fontsize=9 if not values else 7)
    ax.xaxis.tick_top()
    if values:
        ax.set_xlabel('Bank 0～31（每欄 4 bits）',fontsize=13,labelpad=15)
        ax.xaxis.set_label_position('top')
    ax.set_yticks([0,15,31,40,47,63,95,127],[str(i) for i in [0,15,31,40,47,63,95,127]],fontsize=10)
    ax.set_ylabel('Row 0～127',fontsize=13)
    ax.set_xticks(np.arange(-.5,32,1),minor=True); ax.set_yticks(np.arange(-.5,128,1),minor=True)
    ax.grid(which='minor',color='#dde5ed',lw=.3); ax.tick_params(which='minor',length=0)
    for y in [31.5,63.5,95.5]: ax.axhline(y,color='#8094a7',lw=1)
    ax.add_patch(Rectangle((3.5,-.5),2,32,fill=False,ec=teal,lw=2.5))
    if values:
        for r,b in zip(*np.nonzero(mem)):
            ax.text(b,r,f'{mem[r,b]:X}',ha='center',va='center',fontsize=4.4,color=ink)
    for x,y in [(17,15),(17,76),(17,109)]:
        ax.text(x,y,'…',fontsize=28,color='#9caab9',ha='center',va='center',bbox=dict(fc=palette[0],ec='none',pad=2))
    ax.text(17,91,'0 值區域省略',fontsize=15,color='#7c8d9d',ha='center',bbox=dict(fc=palette[0],ec='none'))
    return ax

# Standalone square canvas; left input table is expanded independently of the
# 128-row square memory overview so that all 32 activation bit patterns read well.
fig=plt.figure(figsize=(12,12),dpi=200,facecolor='white')
fig.text(.5,.96,'命令62｜A4輸入與權重配置',ha='center',fontsize=23,color=ink)
fig.text(.5,.915,'左：Group0 的32列輸入放大表　右：128列權重總覽（兩表列高不同）',ha='center',fontsize=12,color=ink)
matrix=square(fig,[.37,.20,.60,.60],True)
matrix.set_ylabel('')
fig.text(.16,.87,'欄位順序：LSB → MSB' if args.lsb_layout else '依時間順序：MSB → LSB',ha='center',fontsize=12,color=teal)
inputs=fig.add_axes([.035,.20,.235,.60])
inputs.set(xlim=(-1.5,4.5),ylim=(31.5,-.5)); inputs.axis('off')
activation=np.array([(5*r+3)&15 for r in range(32)])
bits=((activation[:,None]>>np.array([3,2,1,0]))&1)
assert np.all((bits*np.array([8,4,2,1])).sum(axis=1)==activation)
columns=[(-1,'A'),(0,'A[0]'),(1,'A[1]'),(2,'A[2]'),(3,'A[3]'),(4,'Row')] if args.lsb_layout else [(-1,'Row'),(0,'A[3]'),(1,'A[2]'),(2,'A[1]'),(3,'A[0]'),(4,'A')]
for x,name in columns:
    inputs.text(x,-1.05,name,ha='center',va='center',fontsize=9,color=teal)
for r in range(32):
    inputs.text(-1,r,str(activation[r] if args.lsb_layout else r),ha='center',va='center',fontsize=8,color=ink)
    inputs.text(4,r,str(r if args.lsb_layout else activation[r]),ha='center',va='center',fontsize=8,color=ink)
    for b in range(4):
        bit_value=bits[r,3-b if args.lsb_layout else b]
        inputs.add_patch(Rectangle((b-.5,r-.5),1,1,fc='#bce8d9' if bit_value else '#f0f3f6',ec='white',lw=.5))
        inputs.text(b,r,str(bit_value),ha='center',va='center',fontsize=9,color=teal if bit_value else '#8b97a4')
fig.text(.16,.17,'每一欄＝一個32-bit plane\nA欄為有效activation（十進位）',ha='center',fontsize=10,color=ink)
matrix.annotate('Group0 / Pair2\nBank4、5同用這32個A',xy=(4.5,15),xytext=(17,25),
                fontsize=10,color=teal,ha='center',arrowprops=dict(arrowstyle='->',color=teal,lw=1.5),
                bbox=dict(fc='white',ec='none',pad=3))
fig.text(.67,.17,'綠：CIM目標　藍：Burst　橘：一般Write\n權重為HEX；0以 … 省略；已寫入0仍有色塊',ha='center',fontsize=10,color=ink)
fig.text(.5,.105,'4欄＝4個有效 bit-plane，不是4個 Master clocks',ha='center',fontsize=16,color=teal)
fig.text(.5,.07,'實際送入：0、0、0、0、A[3]、A[2]、A[1]、A[0]；每plane＝8 Load＋1 Sample',ha='center',fontsize=11,color=ink)
fig.text(.5,.035,'有效Sample：T46／T55／T64／T73（相對接受命令T0）；整筆CIM仍為91 clocks。',ha='center',fontsize=11,color=ink)
stem='before_cmd62_square_A_lsb_to_msb_row' if args.lsb_layout else 'before_cmd62_square'
for ext in ['png','svg']: fig.savefig(out/f'{stem}.{ext}',facecolor='white')
plt.close(fig)
if args.lsb_layout:
    print('Created reordered activation figure:',stem)
    raise SystemExit(0)

# 16:9 slide: square overview on left, legible selected values on right.
fig=plt.figure(figsize=(19.2,10.8),dpi=100,facecolor='white')
ax=fig.add_axes([0,0,1,1]); ax.set(xlim=(0,1920),ylim=(1080,0)); ax.axis('off')
def txt(x,y,s,size=20,color=ink): ax.text(x,y,s,fontsize=size,color=color,va='center',linespacing=1.45)
txt(70,65,'命令62：從權重配置到 A4W8 結果',30)
txt(70,120,'128 × 32 Bank 正方形總覽｜0 以 … 省略｜每格代表 4-bit 權重',17)
square(fig,[.06,.12,780/1920,780/1080])
txt(105,1000,'綠：CIM 目標　　藍：Burst 9　　橘：Write 2／4／5',15)

ax.add_patch(FancyBboxPatch((1010,170),840,170,boxstyle='round,pad=0,rounding_size=16',fc='#e8f7f1',ec=teal,lw=1.5))
txt(1040,207,'只選 Group0 × Pair2',25,teal)
txt(1040,257,'Row0～31；Bank4 = 高4 bits，Bank5 = 低4 bits',17)
txt(1040,302,'其餘已寫入區域，不參與這次 CIM。',17)
txt(1035,385,'綠色區域：權重節錄（其餘非零值見完整表）',17)
cols=[1060,1240,1420,1620]
for x,s in zip(cols,['Row','Bank4','Bank5','W8']): txt(x,430,s,18,teal)
for j,r in enumerate([0,1,2,3,30,31]):
    y=475+j*38
    for x,s in zip(cols,[str(r),f'{mem[r,4]:X}',f'{mem[r,5]:X}',f'{16*mem[r,4]+mem[r,5]:02X}']): txt(x,y,s,18)
txt(1040,720,'例：Row0，A=3、W=0x23=35',18)
txt(1040,763,'3×2 → Even=6；3×3 → Odd=9；16×6+9=105',16)
ax.add_patch(FancyBboxPatch((1010,810),840,145,boxstyle='round,pad=0,rounding_size=16',fc='#eef4fa',ec='#bdd0df',lw=1.5))
txt(1040,847,'32列累加：Even = 2,124；Odd = 1,744',21)
txt(1040,909,'完整結果 = (2,124 << 4) + 1,744 = 35,728',22,teal)
txt(1020,995,'色塊保留寫入0的紀錄；如 Row47／Bank22、23。',14)
txt(1020,1032,'左圖為位置摘要；數值可在正方形大圖／Excel 放大查看。',14)
for ext in ['png','svg']: fig.savefig(out/f'cmd62_square_slide_16x9.{ext}',facecolor='white')
plt.close(fig)
print('Created square PNG/SVG and 16:9 slide PNG/SVG.')

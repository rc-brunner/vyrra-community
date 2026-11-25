"""Render Vyrra's Studio, Felt and Porcelain pairs from Kenney Interface Sounds (CC0).

Run with Python, NumPy, SciPy, and soundfile. Supply the original pack ZIP and an
output directory. Classic and Soft click are separate Vyrra-authored recordings.
"""
import argparse
import hashlib
import io
import math
import zipfile
from pathlib import Path
import numpy as np
import soundfile as sf
from scipy import signal

RATE = 44100
PACK_SHA = 'f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232'
# File, duration (ms), high cut, transient gain, body modes (Hz, time constant ms, relative amplitude).
RECIPES = {
    'studio-engage': ('click_002', 48, 3400, .60, [(790,6.2,1),(1460,3.4,.39),(490,9,.23)]),
    'studio-release': ('click_005', 63, 2400, .58, [(435,10,1),(780,6,.39),(1240,2.8,.17)]),
    'felt-engage': ('click_005', 55, 2200, .29, [(450,8,1),(940,5,.42),(260,10,.26)]),
    'felt-release': ('click_005', 77, 1450, .22, [(248,13,1),(540,8,.57),(900,3,.21)]),
    'porcelain-engage': ('glass_006', 61, 4700, .43, [(1470,8,1),(2310,5,.44),(760,9,.31)]),
    'porcelain-release': ('glass_006', 70, 3400, .32, [(885,10,1),(1490,6,.4),(520,11,.25)]),
}

def perceptual_filter(x):
    """BS.1770 K-weighting at our sampling rate. No LUFS gating of short transients."""
    f, q, gain = 1681.974450955533, .7071752369554196, 3.999843853973347
    k = np.tan(np.pi*f/RATE); vh=10**(gain/20); vb=vh**.4996667741545416; d=1+k/q+k*k
    x=signal.lfilter([(vh+vb*k/q+k*k)/d, 2*(k*k-vh)/d, (vh-vb*k/q+k*k)/d], [1,2*(k*k-1)/d,(1-k/q+k*k)/d], x)
    k=np.tan(np.pi*38.13547087602444/RATE); q=.5003270373238773; d=1+k/q+k*k
    return signal.lfilter([1,-2,1],[1,2*(k*k-1)/d,(1-k/q+k*k)/d],x)

def fixed_window_db(x):
    window=np.zeros(RATE//10); n=min(len(x),len(window));window[:n]=x[:n]
    return 10*np.log10(max(np.mean(perceptual_filter(window)**2), 1e-20))

def layer(pack, name, n, cutoff):
    x,rate=sf.read(io.BytesIO(pack.read('Audio/'+name+'.ogg')),always_2d=True)
    x=x.mean(axis=1); base=math.gcd(rate,RATE); x=signal.resample_poly(x,RATE//base, rate//base)
    attack=np.flatnonzero(abs(x)>max(abs(x))*.025)[0]; x=x[max(0,attack-8):]
    out=np.zeros(n);count=min(n,len(x));out[:count]=x[:count]
    out=signal.sosfilt(signal.butter(3,cutoff,fs=RATE,output='sos'),out)
    t=np.arange(n)/RATE;out*=np.exp(-t/.0065)
    return out/max(abs(out))

def render(pack, name, spec):
    sample,ms,cut,gain,modes=spec; t=np.arange(round(ms*RATE/1000))/RATE
    body=sum(a*np.sin(2*np.pi*f*t)*np.exp(-1000*t/decay) for f,decay,a in modes)
    texture=layer(pack,sample,len(t),cut)
    if name.startswith('studio'):
        # A small second contact belongs to the same click, well inside a single gesture.
        delay=round((.0038 if name.endswith('engage') else .0051)*RATE)
        texture[delay:]+=texture[:-delay]*.16
    x=body/max(abs(body)) + gain*texture
    x=signal.sosfilt(signal.butter(2,95,fs=RATE,btype='highpass',output='sos'),x)
    attack=round((.00065 if name.startswith('felt') else .00030)*RATE);x[:attack]*=np.sin(np.linspace(0,np.pi/2,attack))**2
    fade=round(.004*RATE);x[-fade:]*=np.cos(np.linspace(0,np.pi/2,fade))**2
    # Same start level across the three materials. Finish cues are 2 dB quieter.
    target=-34 if name.endswith('engage') else -36
    x*=10**((target-fixed_window_db(x))/20)
    if max(abs(signal.resample_poly(x,4,1)))>.40: raise ValueError(f'Peak limit exceeded: {name}')
    return x

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('pack',type=Path);parser.add_argument('out',type=Path);args=parser.parse_args()
    if hashlib.sha256(args.pack.read_bytes()).hexdigest()!=PACK_SHA: raise ValueError('Unexpected Kenney source archive')
    args.out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.pack) as pack:
        for name,spec in RECIPES.items():sf.write(args.out/(name+'.wav'),render(pack,name,spec),RATE,subtype='PCM_16')
if __name__=='__main__':main()

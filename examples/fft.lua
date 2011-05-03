
 -- Fast Fourier Transform Examples / fft.lua
 -- 
 -- Copyright (C) 2009, 2010 Francesco Abbate
 -- 
 -- This program is free software; you can redistribute it and/or modify
 -- it under the terms of the GNU General Public License as published by
 -- the Free Software Foundation; either version 3 of the License, or (at
 -- your option) any later version.
 -- 
 -- This program is distributed in the hope that it will be useful, but
 -- WITHOUT ANY WARRANTY; without even the implied warranty of
 -- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 -- General Public License for more details.
 -- 
 -- You should have received a copy of the GNU General Public License
 -- along with this program; if not, write to the Free Software
 -- Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

use 'math'
use 'graph'
use 'gsl'

function demo1()
   local n, ncut = 256, 16

   local sq = matrix.new(n, 1, |i| i < n/3 and 0 or (i < 2*n/3 and 1 or 0))

   local pt = plot('Original signal / reconstructed')
   local pf = plot('FFT Power Spectrum')

   pt:addline(filine(|i| sq[i], n), 'black')

   local ft = fft(sq, true)

   pf:add(ibars(isample(|k| complex.abs(ft:get(k)), 0, 60)), 'black')

   for k=ncut, n/2 do ft:set(k,0) end
   sqt = fftinv(ft, true)

   pt:addline(filine(|i| sqt[i], n), 'red')

   pf:show()
   pt:show()

   return pt, pf
end

function demo2()
   local n, ncut, order = 512, 11, 8
   local x1 = besselJzero(order, 14)
   local xsmp = |k| x1*(k-1)/(n-1)

   local bess = matrix.new(n, 1, |i| besselJ(order, xsmp(i)))

   local p = plot('Original signal / reconstructed')
   p:addline(filine(|i| bess[i], n), 'black')

   local ft = fft(bess)

   fftplot = plot('FFT power spectrum')
   bars = ibars(isample(|k| complex.abs(ft:get(k)), 0, 60))
   fftplot:add(bars, 'darkgreen')
   fftplot:addline(bars, 'black')
   fftplot:show()

   for k=ncut, n/2 do ft:set(k,0) end
   local bessr = fftinv(ft)

   p:addline(filine(|i| bessr[i], n), 'red', {{'dash', 7, 3}})
   p:show()

   return p, fftplot
end

echo 'demo1() - GSL example with square function and frequency cutoff'
echo 'demo2() - frequency cutoff example on bessel function'

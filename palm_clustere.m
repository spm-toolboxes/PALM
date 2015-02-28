function [maxsize,clstat,sizes] = palm_clustere(X,y,thr,opts,plm)
% Compute cluster extent statistics, for volume or surface
% data (voxelwise or facewise).
% 
% Usage:
% [maxsize,clstat,sizes] = palm_clustere(X,y,thr,opts,plm)
% 
% Inputs:
% - X    : Statistical map.
% - y    : Modality index (of those stored in the plm struct).
% - thr  : Cluster-forming threshold.
% - opts : Struct with PALM options.
% - plm  : Struct with PALM data.
% 
% Outputs:
% - maxsize : Largest cluster extent.
% - clstat  : Thresholded map with the cluster sizes (cluster statistic).
% - sizes   : Vector with all cluster sizes.
% 
% _____________________________________
% Anderson M. Winkler
% FMRIB / University of Oxford
% Sep/2013
% http://brainder.org

% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
% PALM -- Permutation Analysis of Linear Models
% Copyright (C) 2015 Anderson M. Winkler
% 
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% any later version.
% 
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% 
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <http://www.gnu.org/licenses/>.
% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

% Choose an appropriate mask struct.
if opts.NPC || opts.MV,
    S = plm.maskinter;
else
    if plm.nmasks == 1,
        S = plm.masks{1};
    else
        S = plm.masks{y};
    end
end

% Inject the data and threshold it.
mask    = S.data;
D       = double(S.data);
D(mask) = X;
D       = D >= thr;

% Do the labelling
if plm.Yisvol(y),
    
    % Volume (voxelwise data)
    % bwconncomp is slightly faster and
    % less memory intensive than bwlabel
    CC = bwconncomp(D);

elseif plm.Yisvtx(y),
    
    % Vertexwise surface data
    dpxl = palm_vtxlabel(D,plm.srf{y}.data.fac);

elseif plm.Yisfac(y),
    
    % Facewise surface data
    dpxl = palm_faclabel(D,plm.srf{y}.data.fac);
    
end

% Compute the sizes and the statistic
sizes = [];
if plm.Yisvol(y),
    
    % Here cellfun is ~30% faster than doing as a loop
    sizes = cellfun(@numel,CC.PixelIdxList);
    
    % Compute the statistic image (this should be for the 1st perm only)
    if nargout > 1,
        clstat = zeros(size(D));
        for c = 1:CC.NumObjects,
            clstat(CC.PixelIdxList{c}) = sizes(c);
        end
        clstat = clstat(mask)';
    end
    
elseif plm.Yisvtx(y) || plm.Yisfac(y),
    
    % Compute the cluster stats
    U     = unique(dpxl(dpxl>0))';
    sizes = zeros(size(U));
    for u = 1:numel(U),
        sizes(u) = sum(plm.Yarea{y}(dpxl == U(u)));
    end
    
    % Compute the statistic image (this is normally for the 1st perm only)
    if nargout > 1,
        clstat = zeros(size(D));
        for u = 1:numel(U),
            clstat(dpxl == U(u)) = sizes(u);
        end
        clstat = clstat(mask)';
    end
end

% In fact, only the max matters, because the uncorrected cluster extent
% doesn't make much sense (probably TFCE doesn't make sense either for
% the same reason...). Make sure the output isn't empty.
if isempty(sizes),
    sizes = 0;
end
maxsize = max(sizes);
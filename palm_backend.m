function palm_backend(varargin)
% This is the core PALM function.
%
% _____________________________________
% Anderson M. Winkler
% FMRIB / University of Oxford
% Oct/2014
% http://brainder.org

% Take the arguments. Save a small log if needed.
% clear global plm opts % comment for debugging
%global plm opts; % uncomment for debugging
[opts,plm] = palm_takeargs(varargin{:});

% Variables to store stuff for later.
plm.X        = cell(plm.nM,1); % effective regressors
plm.Z        = cell(plm.nM,1); % nuisance regressors
plm.eCm      = cell(plm.nM,1); % effective contrast (for Mp)
plm.eCx      = cell(plm.nM,1); % effective contrast (for the effective regressors only)
plm.eC       = cell(plm.nM,1); % final effective contrast (depends on the method)
plm.Mp       = cell(plm.nM,1); % partitioned model, joined
plm.rmethod  = cell(plm.nM,1); % regression method (to allow the case of 'noz')
plm.nEV      = cell(plm.nM,1); % number of regressors
plm.Hm       = cell(plm.nM,1); % hat (projection) matrix
plm.Rm       = cell(plm.nM,1); % residual forming matrix
plm.dRm      = cell(plm.nM,1); % diagonal elements of the residual forming matrix
plm.Gname    = cell(plm.nM,1); % name of the statistic for each contrast
plm.rC       = cell(plm.nM,1); % rank of each contrast, but can be 0 after conversion to z-score
plm.rC0      = cell(plm.nM,1); % original rank of each contrast, before conversion to z-score
plm.rM       = cell(plm.nM,1); % rank of the design matrix
prepglm      = cell(plm.nM,1); % to store the function that prepares data for the regression
fastpiv      = cell(plm.nM,1); % to store the function that calculates the pivotal statistic
G            = cell(plm.nY,1); % to store G at each permutation
df2          = cell(plm.nY,1); % to store df2 at each permutation
plm.Gpperm   = cell(plm.nY,1); % counter, for the permutation p-value
plm.G        = cell(plm.nY,1); % for the unpermuted G (and to be saved)
plm.df2      = cell(plm.nY,1); % for the unpermuted df2 (and to be saved)
plm.Gmax     = cell(plm.nY,1); % to store the max statistic (Y collapses)
plm.nP       = cell(plm.nM,1); % number of permutations for each contrast
plm.evperdat = cell(plm.nM,1); % whether it should be one EV per datapoint for this design

% Complete the lower levels (for the inner loops) for the variables above
for m = 1:plm.nM,
    plm.X      {m} = cell (plm.nC(m),1);
    plm.Z      {m} = cell (plm.nC(m),1);
    plm.eCm    {m} = cell (plm.nC(m),1);
    plm.eCx    {m} = cell (plm.nC(m),1);
    plm.eC     {m} = cell (plm.nC(m),1);
    plm.Mp     {m} = cell (plm.nC(m),1);
    plm.rmethod{m} = cell (plm.nC(m),1);
    plm.nEV    {m} = zeros(plm.nC(m),1);
    plm.Hm     {m} = cell (plm.nC(m),1);
    plm.Rm     {m} = cell (plm.nC(m),1);
    plm.dRm    {m} = cell (plm.nC(m),1);
    plm.Gname  {m} = cell (plm.nC(m),1);
    plm.rC     {m} = zeros(plm.nC(m),1);
    plm.rC0    {m} = zeros(plm.nC(m),1);
    plm.rM     {m} = zeros(plm.nC(m),1);
    prepglm    {m} = cell (plm.nC(m),1);
    fastpiv    {m} = cell (plm.nC(m),1);
    plm.nP     {m} = zeros(plm.nC(m),1);
end
for y = 1:plm.nY,
    G          {y} = cell(plm.nM,1);
    df2        {y} = cell(plm.nM,1);
    plm.Gpperm {y} = cell(plm.nM,1);
    plm.G      {y} = cell(plm.nM,1);
    plm.df2    {y} = cell(plm.nM,1);
    plm.Gmax   {y} = cell(plm.nM,1);
    if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
    for m = loopM,
        G         {y}{m} = cell(plm.nC(m),1);
        df2       {y}{m} = cell(plm.nC(m),1);
        plm.Gpperm{y}{m} = cell(plm.nC(m),1);
        plm.G     {y}{m} = cell(plm.nC(m),1);
        plm.df2   {y}{m} = cell(plm.nC(m),1);
        plm.Gmax  {y}{m} = cell(plm.nC(m),1);
        for c = 1:plm.nC(m),
            plm.Gpperm{y}{m}{c} = zeros(1,size(plm.Yset{y},2));
        end
    end
end
if opts.draft,
    plm.Gppermp = plm.Gpperm; % number of perms done, for the draft mode
end
if opts.savemetrics,
    plm.metr    = plm.Gname;  % to store permutation metrics
end

% Spatial stats, univariate
if opts.clustere_uni.do,
    plm.Gcle    = cell(plm.nY,1); % to store cluster extent statistic
    plm.Gclemax = cell(plm.nY,1); % for the max cluster extent
    for y = 1:plm.nY,
        plm.Gcle   {y} = cell(plm.nM,1);
        plm.Gclemax{y} = cell(plm.nM,1);
        if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
        for m = loopM,
            plm.Gcle   {y}{m} = cell(plm.nC(m),1);
            plm.Gclemax{y}{m} = cell(plm.nC(m),1);
        end
    end
end
if opts.clusterm_uni.do,
    plm.Gclm    = cell(plm.nY,1); % to store cluster mass statistic
    plm.Gclmmax = cell(plm.nY,1); % for the max cluster mass
    for y = 1:plm.nY,
        plm.Gclm   {y} = cell(plm.nM,1);
        plm.Gclmmax{y} = cell(plm.nM,1);
        if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
        for m = loopM,
            plm.Gclm   {y}{m} = cell(plm.nC(m),1);
            plm.Gclmmax{y}{m} = cell(plm.nC(m),1);
        end
    end
end
if opts.tfce_uni.do,
    Gtfce          = cell(plm.nY,1); % to store TFCE at each permutation
    plm.Gtfcepperm = cell(plm.nY,1); % counter, for the TFCE p-value
    plm.Gtfce      = cell(plm.nY,1); % to store TFCE statistic
    plm.Gtfcemax   = cell(plm.nY,1); % for the max TFCE statistic
    for y = 1:plm.nY,
        Gtfce         {y} = cell(plm.nM,1);
        plm.Gtfcepperm{y} = cell(plm.nM,1);
        plm.Gtfce     {y} = cell(plm.nM,1);
        plm.Gtfcemax  {y} = cell(plm.nM,1);
        if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
        for m = loopM,
            Gtfce         {y}{m} = cell(plm.nC(m),1);
            plm.Gtfcepperm{y}{m} = cell(plm.nC(m),1);
            plm.Gtfce     {y}{m} = cell(plm.nC(m),1);
            plm.Gtfcemax  {y}{m} = cell(plm.nC(m),1);
        end
    end
end

% Variables for NPC
if opts.NPC,
    plm.npcstr = '_npc_';                      % default string for the filenames.
    if       opts.npcmod && ~ opts.npccon,
        Gnpc          = cell(1);              % to store the G-stats ready for NPC
        df2npc        = cell(1);              % to store the df2 ready for NPC
        Gnpc      {1} = zeros(plm.nY,plm.Ysiz(1));
        df2npc    {1} = zeros(plm.nY,plm.Ysiz(1));
        T             = cell(plm.nM,plm.nC);  % to store T at each permutation
        plm.Tpperm    = cell(plm.nM,plm.nC);  % counter, for the combined p-value
        Tppara        = cell(plm.nM,plm.nC);  % for the combined parametric p-value
        plm.Tmax      = cell(plm.nM,plm.nC);  % to store the max combined statistic
    elseif  ~ opts.npcmod &&   opts.npccon,
        Gnpc          = cell(plm.nY,1);
        df2npc        = cell(plm.nY,1);
        if opts.designperinput,
            for y = 1:plm.nY,
                Gnpc  {y} = zeros(plm.nC(y),plm.Ysiz(y));
                df2npc{y} = zeros(plm.nC(y),plm.Ysiz(y));
            end
        else
            for y = 1:plm.nY,
                Gnpc  {y} = zeros(sum(plm.nC),plm.Ysiz(y));
                df2npc{y} = zeros(sum(plm.nC),plm.Ysiz(y));
            end
        end
        T             = cell(plm.nY,1);
        plm.Tpperm    = cell(plm.nY,1);
        Tppara        = cell(plm.nY,1);
        plm.Tmax      = cell(plm.nY,1);
    elseif   opts.npcmod &&   opts.npccon,
        Gnpc          = cell(1);
        df2npc        = cell(1);
        if opts.designperinput,
            Gnpc  {1} = zeros(plm.nY*plm.nC(1),plm.Ysiz(1));
            df2npc{1} = zeros(plm.nY*plm.nC(1),plm.Ysiz(1));
        else
            Gnpc  {1} = zeros(plm.nY*sum(plm.nC),plm.Ysiz(1));
            df2npc{1} = zeros(plm.nY*sum(plm.nC),plm.Ysiz(1));
        end
        T             = cell(1);
        plm.Tpperm    = cell(1);
        Tppara        = cell(1);
        plm.Tmax      = cell(1);
    end
    
    % Spatial stats, NPC
    if opts.clustere_npc.do,
        plm.Tcle     = plm.Tmax;   % to store cluster extent NPC statistic
        plm.Tclemax  = plm.Tmax;   % for the max cluster extent NPC
    end
    if opts.clusterm_npc.do,
        plm.Tclm     = plm.Tmax;   % to store cluster mass NPC statistic
        plm.Tclmmax  = plm.Tmax;   % for the max cluster mass NPC
    end
    if opts.tfce_npc.do,
        Ttfce          = plm.Tmax;   % to store TFCE at each permutation
        plm.Ttfcepperm = plm.Tmax;   % counter, for the TFCE p-value
        plm.Ttfce      = plm.Tmax;   % for the unpermuted TFCE
        plm.Ttfcemax   = plm.Tmax;   % to store the max TFCE statistic
    end
end

% Variables for MV
if opts.MV,
    plm.mvstr          = '_mv';           % default string for the filenames.
    Q                  = cell(plm.nM,1);  % to store MV G at each permutation
    plm.Qname          = cell(plm.nM,1);
    Qdf2               = cell(plm.nM,1);  % to store MV df2 at each permutation
    plm.Qpperm         = cell(plm.nM,1);  % counter, for the MV permutation p-value
    Qppara             = cell(plm.nM,1);  % for the MV parametric p-value
    fastmv             = cell(plm.nM,1);
    pparamv            = cell(plm.nM,1);
    plm.Qmax           = cell(plm.nM,1);  % to store the max multivariate statistic
    
    % Spatial stats, multivariate
    if opts.clustere_mv.do,
        plm.Qcle       = cell(plm.nM,1);  % to store cluster extent NPC statistic
        plm.Qclemax    = cell(plm.nM,1);  % for the max cluster extent NPC
    end
    if opts.clusterm_mv.do,
        plm.Qclm       = cell(plm.nM,1);  % to store cluster mass NPC statistic
        plm.Qclmmax    = cell(plm.nM,1);  % for the max cluster mass NPC
    end
    if opts.tfce_mv.do,
        Qtfce          = cell(plm.nM,1);  % to store TFCE at each permutation
        plm.Qtfcepperm = cell(plm.nM,1);  % counter, for the TFCE p-value
        plm.Qtfce      = cell(plm.nM,1);  % for the unpermuted TFCE
        plm.Qtfcemax   = cell(plm.nM,1);  % to store the max TFCE statistic
    end
    
    % Lower levels of these variables
    for m = 1:plm.nM,
        Q{m} = cell(plm.nC(m),1);
        plm.Qname{m}      = cell(plm.nC(m),1);
        Qdf2{m}           = cell(plm.nC(m),1);
        plm.Qpperm{m}     = cell(plm.nC(m),1);
        Qppara{m}         = cell(plm.nC(m),1);
        fastmv{m}         = cell(plm.nC(m),1);
        pparamv{m}        = cell(plm.nC(m),1);
        plm.Qmax{m}       = cell(plm.nC(m),1);
        plm.Qcle{m}       = cell(plm.nC(m),1);
        plm.Qclemax{m}    = cell(plm.nC(m),1);
        plm.Qclm{m}       = cell(plm.nC(m),1);
        plm.Qclmmax{m}    = cell(plm.nC(m),1);
        Qtfce{m}          = cell(plm.nC(m),1);
        plm.Qtfcepperm{m} = cell(plm.nC(m),1);
        plm.Qtfce{m}      = cell(plm.nC(m),1);
        plm.Qtfcemax{m}   = cell(plm.nC(m),1);
    end
    if opts.draft,
        plm.Qppermp  = plm.Qpperm;        % number of perms done, for the draft mode
    end
end

% Variables for CCA
if opts.CCA,
    plm.mvstr    = '';                         % default string for the filenames.
end

% Inital strings to save the file names later.
ystr = cell(plm.nY,1); for y = 1:plm.nY; ystr{y} = ''; end
mstr = cell(plm.nM,1); for m = 1:plm.nM; mstr{m} = ''; end
cstr = cell(max(plm.nC),1); for c = 1:max(plm.nC); cstr{c} = ''; end

% Create the function handles for the NPC.
if opts.NPC,
    isnichols = false;
    plm.Tname = lower(opts.npcmethod);
    switch plm.Tname,
        case 'tippett',
            fastnpc    = @(G,df1,df2)tippett(G,df1,df2);
            pparanpc   = @(T,nG)tippettp(T,nG);
            npcrev     = true;
        case 'fisher',
            fastnpc    = @(G,df1,df2)fisher(G,df1,df2);
            pparanpc   = @(T)fisherp(T,nG);
            npcrev     = false;
        case 'pearson-david',
            fastnpc    = @(G,df1,df2)pearsondavid(G,df1,df2);
            pparanpc   = @(T,nG)pearsondavidp(T,nG);
            npcrev     = false;
        case 'stouffer',
            fastnpc    = @(G,df1,df2)stouffer(G,df1,df2);
            pparanpc   = @(T,nG)stoufferp(T,nG);
            npcrev     = false;
        case 'wilkinson',
            fastnpc    = @(G,df1,df2)wilkinson(G,df1,df2,plm.npcparm);
            pparanpc   = @(T,nG)wilkinsonp(T,nG,plm.npcparm);
            npcrev     = false;
        case 'winer'
            fastnpc    = @(G,df1,df2)winer(G,df1,df2);
            pparanpc   = @(T,nG)winerp(T,nG);
            npcrev     = false;
        case 'edgington',
            fastnpc    = @(G,df1,df2)edgington(G,df1,df2);
            pparanpc   = @(T,nG)edgingtonp(T,nG);
            npcrev     = true;
        case 'mudholkar-george',
            fastnpc    = @(G,df1,df2)mudholkargeorge(G,df1,df2);
            pparanpc   = @(T,nG)mudholkargeorgep(T,nG);
            npcrev     = false;
        case 'friston',
            fastnpc    = @(G,df1,df2)fristonnichols(G,df1,df2);
            pparanpc   = @(T,nG)fristonp(T,nG,plm.npcparm);
            npcrev     = true;
        case 'darlington-hayes',
            fastnpc    = @(G,df1,df2)darlingtonhayes(G,df1,df2,plm.npcparm);
            npcrev     = false;
        case 'zaykin',
            fastnpc    = @(G,df1,df2)zaykin(G,df1,df2,plm.npcparm);
            pparanpc   = @(T,nG)zaykinp(T,nG,plm.npcparm);
            npcrev     = false;
        case 'dudbridge-koeleman',
            fastnpc    = @(G,df1,df2)dudbridgekoeleman(G,df1,df2,plm.npcparm);
            pparanpc   = @(T,nG)dudbridgekoelemanp(T,nG,plm.npcparm);
            npcrev     = false;
        case 'dudbridge-koeleman2',
            fastnpc    = @(G,df1,df2)dudbridgekoeleman2(G,df1,df2,plm.npcparm,plm.npcparm2);
            pparanpc   = @(T,nG)dudbridgekoeleman2p(T,nG,plm.npcparm,plm.npcparm2);
            npcrev     = false;
        case 'nichols',
            fastnpc    = @(G,df1,df2)fristonnichols(G,df1,df2);
            pparanpc   = @(T,nG)nicholsp(T,nG);
            npcrev     = true;
            isnichols  = true;
        case 'taylor-tibshirani',
            fastnpc    = @(G,df1,df2)taylortibshirani(G,df1,df2);
            pparanpc   = @(T,nG)taylortibshiranip(T,nG);
            npcrev     = false;
        case 'jiang',
            fastnpc    = @(G,df1,df2)jiang(G,df1,df2,plm.npcparm);
            npcrev     = false;
    end
    
    % For the NPC methods in which the most significant stats are the
    % smallest, rather than the largest, use reverse comparisons.
    if npcrev,
        npcrel  = @le;
        npcextr = @min;
    else
        npcrel  = @ge;
        npcextr = @max;
    end
end

% Create the permutation set, while taking care of the synchronized
% permutations (see the inner loop below)
if opts.syncperms,
    if isempty(plm.EB),
        if opts.savemetrics,
            [plm.Pset,plm.nP{1}(1),plm.metr{1}{1}] = ...
                palm_shuffree(plm.seq{1}{1},opts.nP0, ...
                opts.cmcp,opts.EE,opts.ISE,false);
        else
            [plm.Pset,plm.nP{1}(1)] = ...
                palm_shuffree(plm.seq{1}{1},opts.nP0, ...
                opts.cmcp,opts.EE,opts.ISE,false);
        end
    else
        if opts.savemetrics,
            [plm.Pset,plm.nP{1}(1),plm.metr{1}{1}] = ...
                palm_shuftree(opts,plm,1,1);
        else
            [plm.Pset,plm.nP{1}(1)] = ...
                palm_shuftree(opts,plm,1,1);
        end
    end
    P_outer = 1:plm.nP{1}(1);
    fprintf('Building null distribution.\n');
else
    P_outer = 1;
end

% To calculate progress
if opts.syncperms,
    ProgressNum = 0;
    if opts.designperinput,
        ProgressDen = sum(plm.nC) * plm.nP{1}(1);
    else
        ProgressDen = sum(plm.nC) * plm.nP{1}(1) * plm.nY;
    end
else
    ProgressCon = 0;
end

% For each permutation (outer loop)
for po = P_outer,
    
    % For each design matrix
    for m = 1:plm.nM,
        
        % String with the counter
        if po == 1 && (plm.nM > 1 || opts.verbosefilenames),
            mstr{m} = sprintf('_d%d',m);
        end
        
        % For each contrast
        for c = 1:plm.nC(m),
            
            if po == 1,
                
                % String with the counter
                if (plm.nC(m) > 1 || opts.verbosefilenames),
                    ctmp = c + opts.conskipcount;
                    cstr{c} = sprintf('_c%d',ctmp);
                end
                
                if ~ opts.evperdat,
                    
                    % Partition the model, now using the method chosen by the user
                    [plm.X{m}{c},plm.Z{m}{c},plm.eCm{m}{c},plm.eCx{m}{c}] = ...
                        palm_partition(plm.Mset{m},plm.Cset{m}{c},opts.pmethodr);
                    plm.Mp{m}{c} = horzcat(plm.X{m}{c},plm.Z{m}{c}); % partitioned design matrix, joined
                    
                    % To avoid rank deficiency issues after partitioning, remove
                    % columns that are all equal to zero.
                    idx = all(plm.X{m}{c} == 0,1);
                    plm.X  {m}{c}(:,idx) = [];
                    plm.eCx{m}{c}(idx,:) = [];
                    idx = all(plm.Mp{m}{c} == 0,1);
                    plm.Mp {m}{c}(:,idx) = [];
                    plm.eCm{m}{c}(idx,:) = [];
                    
                    % Some methods don't work well if Z is empty, and there is no point in
                    % using any of them all anyway.
                    if isempty(plm.Z{m}{c}),
                        plm.rmethod{m}{c} = 'noz';
                    else
                        plm.rmethod{m}{c} = opts.rmethod;
                    end
                    
                    % Some other variables to be used in the function handles below.
                    plm.nEV{m}(c) = size(plm.Mp{m}{c},2);    % number of regressors in the design
                    plm.rC {m}(c) = rank(plm.eCm{m}{c});     % rank(C), also df1 for all methods
                    
                    % Residual-forming matrix. This is used by the ter Braak method and
                    % also to compute some of the stats later. Note that, even though the
                    % residual-forming matrix changes at every permutation, the trace
                    % for each VG remains unchanged, hence it's not necessary to recompute
                    % it for every permutation.
                    plm.Hm {m}{c} = plm.Mp{m}{c}*pinv(plm.Mp{m}{c});
                    plm.Rm {m}{c} = eye(plm.N) - plm.Hm{m}{c};
                    plm.dRm{m}{c} = diag(plm.Rm{m}{c}); % this is used for the pivotal statistic
                    plm.rM {m}(c) = plm.N - round(sum(plm.dRm{m}{c})); % this is faster than rank(M)
                    
                else
                    % If one EV per datum, this is a simplification of the above, for
                    % what matters, and for speed.
                    plm.rmethod{m}{c} = 'evperdat';
                    plm.eCx    {m}{c} = plm.Cset{m}{c};
                    plm.Mp     {m}{c} = plm.Mset{m};
                    plm.nEV    {m}(c) = 1;
                    plm.rC     {m}(c) = 1;
                    plm.dRm    {m}{c} = 1 - plm.Mset{m}.* ...
                        bsxfun(@rdivide,plm.Mset{m},sum(plm.Mset{m}.*plm.Mset{m},1));
                    plm.rM     {m}(c) = plm.N - 1;
                end
                plm.evperdat   {m}{c} = opts.evperdat;
                
                % Decide which method is going to be used for the regression and
                % permutations, compute some useful matrices for later and create
                % the appropriate function handle to prepare for the model fit.
                % Each of these small functions is a replacement for the generic
                % prototype function 'permglm.m', which is far slower.
                % Note that this swich needs to remain inside the for-loops over
                % designs and contrasts, because they vary. Nonetheless,
                % this all runs just for the 1st permutation.
                isterbraak = false;
                switch lower(plm.rmethod{m}{c}),
                    case 'evperdat',
                        prepglm{m}{c}      = @(P,Y)evperdat(P,Y,m,c,plm);
                        plm.eC {m}{c}      = plm.eCx{m}{c};
                    case 'noz',
                        prepglm{m}{c}      = @(P,Y)noz(P,Y,m,c,plm);
                        plm.eC {m}{c}      = plm.eCx{m}{c};
                    case 'exact',
                        prepglm{m}{c}      = @(P,Y)exact(P,Y,m,c,plm);
                        plm.eC {m}{c}      = plm.eCx{m}{c};
                    case 'draper-stoneman',
                        prepglm{m}{c}      = @(P,Y)draperstoneman(P,Y,m,c,plm);
                        plm.eC {m}{c}      = plm.eCm{m}{c};
                    case 'still-white',
                        plm.Rz {m}{c}      = eye(plm.N) - plm.Z{m}{c}*pinv(plm.Z{m}{c});
                        prepglm{m}{c}      = @(P,Y)stillwhite(P,Y,m,c,plm);
                        plm.eC {m}{c}      = plm.eCx{m}{c};
                    case 'freedman-lane',
                        plm.Hz {m}{c}      = plm.Z{m}{c}*pinv(plm.Z{m}{c});
                        plm.Rz {m}{c}      = eye(plm.N) - plm.Hz{m}{c};
                        prepglm{m}{c}      = @(P,Y)freedmanlane(P,Y,m,c,plm);
                        plm.eC {m}{c}      = plm.eCm{m}{c};
                    case 'terbraak',
                        isterbraak         = true;
                        prepglm{m}{c}      = @(P,Y)terbraak(P,Y,m,c,plm);
                        plm.eC {m}{c}      = plm.eCm{m}{c};
                    case 'kennedy',
                        plm.Rz {m}{c}      = eye(plm.N) - plm.Z{m}{c}*pinv(plm.Z{m}{c});
                        prepglm{m}{c}      = @(P,Y)kennedy(P,Y,m,c,plm);
                        plm.eC {m}{c}      = plm.eCx{m}{c};
                    case 'manly',
                        prepglm{m}{c}      = @(P,Y)manly(P,Y,m,c,plm);
                        plm.eC {m}{c}      = plm.eCm{m}{c};
                    case 'huh-jhun',
                        plm.Rz {m}{c}      = eye(plm.N) - plm.Z{m}{c}*pinv(plm.Z{m}{c});
                        [plm.hjQ{m}{c},D]  = schur(plm.Rz{m}{c});
                        D                  = abs(diag(D)) < 10*eps;
                        plm.hj {m}{c}(:,D) = [];
                        prepglm{m}{c}      = @(P,Y)huhjhun(P,Y,m,c,plm);
                        plm.eC {m}{c}      = plm.eCx{m}{c};
                    case 'smith',
                        plm.Rz {m}{c}      = eye(plm.N) - plm.Z{m}{c}*pinv(plm.Z{m}{c});
                        prepglm{m}{c}      = @(P,Y)smith(P,Y,m,c,plm);
                        plm.eC {m}{c}      = plm.eCm{m}{c};
                end
                
                % To gain in speed, choose an appropriate faster replacement for the
                % original 'pivotal.m', depending on the rank of the contrast and on
                % the presence or not of variance groups. Also define the name of the
                % statistic to save as a file later.
                if opts.pearson,
                    if     plm.rC{m}(c) == 1,
                        plm.Gname{m}{c} = '_rstat';
                        fastpiv  {m}{c} = @(M,psi,Y)fastr(M,psi,Y,m,c,plm);
                    elseif plm.rC{m}(c) >  1,
                        plm.Gname{m}{c} = '_rsqstat';
                        fastpiv  {m}{c} = @(M,psi,Y)fastrsq(M,psi,Y,m,c,plm);
                    end
                else
                    if     plm.rC{m}(c) == 1 && plm.nVG == 1,
                        plm.Gname{m}{c} = '_tstat';
                        fastpiv  {m}{c} = @(M,psi,res)fastt(M,psi,res,m,c,plm);
                    elseif plm.rC{m}(c) >  1 && plm.nVG == 1,
                        plm.Gname{m}{c} = '_fstat';
                        fastpiv  {m}{c} = @(M,psi,res)fastf(M,psi,res,m,c,plm);
                    elseif plm.rC{m}(c) == 1 && plm.nVG >  1,
                        plm.Gname{m}{c} = '_vstat';
                        fastpiv  {m}{c} = @(M,psi,res)fastv(M,psi,res,m,c,plm);
                    elseif plm.rC{m}(c) >  1 && plm.nVG >  1,
                        plm.Gname{m}{c} = '_gstat';
                        fastpiv  {m}{c} = @(M,psi,res)fastg(M,psi,res,m,c,plm);
                    end
                end
                
                % MV/CCA
                %%% DOUBLE-CHECK THE DEGREES-OF-FREEDOM!!
                if opts.MV,
                    
                    % Make the 3D dataset
                    plm.Yq{m}{c} = cat(3,plm.Yset{:});
                    
                    % Define the functions for the stats. Note that none is
                    % available if nVG > 1, and this should have been
                    % checked when taking the arguments.
                    if plm.rC{m}(c) == 1 && plm.nVG == 1,
                        plm.Qname{m}{c} = '_hotelling'; % this is Hotelling's T^2
                        fastmv   {m}{c} = @(M,psi,res)fasttsq(M,psi,res,m,c,plm);
                        pparamv  {m}{c} = @(Q)fasttsqp(Q,plm.N-plm.rM{m}(c),plm.nY);
                    elseif plm.rC{m}(c) >  1 && plm.nVG == 1,
                        switch lower(opts.mvstat),
                            case 'wilks',
                                plm.Qname{m}{c} = '_wilks'; % This is Wilks' Lambda
                                plm.qfun        = @(H,E)wilks(H,E);
                                pparamv{m}{c}   = @(Q)wilksp(Q, ...
                                    plm.rC{m}(c),plm.N-plm.rM{m}(c),plm.nY);
                            case 'lawley',
                                plm.Qname{m}{c} = '_lawley'; % This is Lawley-Hotelling
                                plm.qfun        = @(H,E)lawley(H,E);
                                pparamv{m}{c}   = @(Q)lawleyp(Q, ...
                                    plm.rC{m}(c),plm.N-plm.rM{m}(c),plm.nY);
                            case 'pillai',
                                plm.Qname{m}{c} = '_pillai';
                                plm.qfun        = @(H,E)pillai(H,E);
                                pparamv{m}{c}   = @(Q)pillaip(Q, ...
                                    plm.rC{m}(c),plm.N-plm.rM{m}(c),plm.nY);
                            case {'roy_ii','roy'},
                                plm.Qname{m}{c} = '_roy';
                                plm.qfun        = @(H,E)roy_ii(H,E);
                                pparamv{m}{c}   = @(Q)roy_iip(Q, ...
                                    plm.rC{m}(c),plm.N-plm.rM{m}(c),plm.nY);
                            case 'roy_iii',
                                plm.Qname{m}{c} = '_roy3';
                                plm.qfun        = @(H,E)roy_iii(H,E);
                        end
                        fastmv{m}{c} = @(M,psi,res)fastq(M,psi,res,m,c,plm);
                    end
                    
                elseif opts.CCA,
                    
                    % Output string
                    plm.Qname{m}{c} = sprintf('_cca%d',opts.ccaparm);
                    
                    % Residual forming matrix (Z only)
                    if strcmpi(plm.rmethod{m}{c},'noz'),
                        plm.Rz{m}{c} = eye(plm.N);
                    elseif ~any(strcmpi(plm.rmethod{m}{c},{ ...
                            'still-white','freedman-lane',  ...
                            'kennedy','huh-jhun','smith'})),
                        plm.Rz{m}{c} = eye(plm.N) - plm.Z{m}{c}*pinv(plm.Z{m}{c});
                    end
                    
                    % Make the 3D dataset & residualise wrt Z
                    plm.Yq{m}{c} = cat(3,plm.Yset{:});
                    for y = 1:plm.nY,
                        plm.Yq{m}{c}(:,:,y) = plm.Rz{m}{c}*plm.Yq{m}{c}(:,:,y);
                    end
                    plm.Yq{m}{c} = permute(plm.Yq{m}{c},[1 3 2]);
                end
            end
            
            % Create the permutation set, while taking care of the synchronized
            % permutations (see the outer loop above)
            if opts.syncperms,
                P_inner = po;
                plm.nP{m}(c) = plm.nP{1}(1);
            else
                if isempty(plm.EB),
                    if opts.savemetrics,
                        [plm.Pset,plm.nP{m}(c),plm.metr{m}{c}] = ...
                            palm_shuffree(plm.seq{m}{c},opts.nP0, ...
                            opts.cmcp,opts.EE,opts.ISE,false);
                    else
                        [plm.Pset,plm.nP{m}(c)] = ...
                            palm_shuffree(plm.seq{m}{c},opts.nP0, ...
                            opts.cmcp,opts.EE,opts.ISE,false);
                    end
                else
                    if opts.savemetrics,
                        [plm.Pset,plm.nP{m}(c),plm.metr{m}{c}] = ...
                            palm_shuftree(opts,plm,m,c);
                    else
                        [plm.Pset,plm.nP{m}(c)] = ...
                            palm_shuftree(opts,plm,m,c);
                    end
                end
                P_inner = 1:plm.nP{m}(c);
                fprintf('Building null distribution.\n');
            end
            
            if po == 1,
                % If the user wants to save the permutations, save the vectors now.
                % This has 3 benefits: (1) the if-test below will run just once, rather
                % than many times inside the loop, (2) if the user only wants the
                % vectors, not the images, he/she can cancel immediately after the
                % text file has been created and (3) having all just as a single big
                % file is more convenient than hundreds of small ones.
                if opts.saveperms,
                    % It's faster to write directly as below than using dlmwrite and
                    % palm_swapfmt.m
                    fid = fopen(sprintf('%s%s%s_permidx.csv',opts.o,mstr{m},cstr{c}),'w');
                    for p = 1:plm.nP{m}(c),
                        fprintf(fid,'%d,',palm_perm2idx(plm.Pset{p})');
                        fseek(fid,-1,'eof');
                        fprintf(fid,'\n');
                    end
                    fclose(fid);
                end
                
                % If the user requests, save the permutation metrics
                if opts.savemetrics,
                    fid = fopen(sprintf('%s%s%s_metrics.csv',opts.o,mstr{m},cstr{c}),'w');
                    fprintf(fid,[ ...
                        'Log of max number of permutations given the tree (W),%f\n' ...
                        'Log of max number of permutations if unrestricted (W0),%f\n' ...
                        'Huberman & Hogg complexity (tree only),%d\n' ...
                        'Huberman & Hogg complexity (tree & design),%d\n' ...
                        'Average Hamming distance (tree only),%f\n' ...
                        'Average Hamming distance (tree & design),%f\n' ...
                        'Average Euclidean distance (tree only),%f\n' ...
                        'Average Euclidean distance (tree & design),%f\n' ...
                        'Average Spearman correlation,%f\n'], plm.metr{m}{c});
                    fclose(fid);
                end
                
                % Some vars for later
                if isterbraak, psi0 = cell(plm.nY,1); end
                if opts.draft, ysel = cell(plm.nY,1); end
                plm.Gmax{y}{m}{c} = zeros(plm.nP{m}(c),1);
                if opts.npcmod && ~ opts.npccon,
                    if isnichols,
                        plm.Tmax{m}{c} = zeros(plm.nP{m}(c),plm.nY);
                    else
                        plm.Tmax{m}{c} = zeros(plm.nP{m}(c),1);
                    end
                end
                if opts.MV,
                    plm.Qmax{m}{c} = zeros(plm.nP{m}(c),1);
                    if ~ opts.draft,
                        psiq = zeros(plm.nEV{m}(c),plm.Ysiz(1),plm.nY);
                        resq = zeros(plm.N,plm.Ysiz(1),plm.nY);
                    end
                end
            end
            
            if ~ opts.syncperms,
                ProgressNum = 0;
            end
            
            % For each permutation (inner loop)
            for p = P_inner,
                
                % For each input dataset
                if opts.designperinput, loopY = m; else loopY = 1:plm.nY; end
                for y = loopY,
                    
                    % Some feedback
                    ProgressNum = ProgressNum + 1;
                    if opts.showprogress,
                        if opts.syncperms,
                            fprintf('%0.3g%%\t [Shuffling %d/%d, Design %d/%d, Contrast %d/%d, Modality %d/%d]\n', ...
                                100*ProgressNum/ProgressDen,...
                                p,plm.nP{m}(c),m,plm.nM,c,plm.nC(m),y,plm.nY);
                        else
                            fprintf('%0.3g%%\t [Design %d/%d, Contrast %d/%d, Shuffling %d/%d, Modality %d/%d]\n', ...
                                100*(ProgressNum/plm.nP{m}(c)/plm.nY + ProgressCon)/sum(plm.nC),...
                                m,plm.nM,c,plm.nC(m),p,plm.nP{m}(c),y,plm.nY);
                        end
                    end
                    
                    % String for the modality index:
                    if p == 1 && (plm.nY > 1 || opts.verbosefilenames),
                        ystr{y} = sprintf('_m%d',y);
                    end
                    
                    % Shuffle the data and/or design.
                    if opts.draft,
                        if p == 1,
                            ysel{y} = true(1,size(plm.Yset{y},2));
                        end
                        [M,Y] = prepglm{m}{c}(plm.Pset{p},plm.Yset{y}(:,ysel{y}));
                    else
                        [M,Y] = prepglm{m}{c}(plm.Pset{p},plm.Yset{y});
                    end
                    
                    % Do the GLM fit.
                    if opts.evperdat,
                        psi = sum(M.*Y,1)./sum(M.*M,1);
                        res = Y - bsxfun(@times,M,psi);
                    else
                        psi = M\Y;
                        res = Y - M*psi;
                    end
                    
                    % Unless this is draft mode, there is no need to fit
                    % again for the MV later
                    if opts.MV && ~ opts.draft,
                        psiq(:,:,y) = psi;
                        resq(:,:,y) = res;
                    end
                    
                    % ter Braak permutes under alternative.
                    if isterbraak,
                        if p == 1,
                            psi0{y} = psi;
                        else
                            psi = psi - psi0{y};
                        end
                    end
                    
                    % Compute the pivotal statistic.
                    if opts.pearson,
                        G  {y}{m}{c} = fastpiv{m}{c}(M,psi,Y);
                        df2{y}{m}{c} = NaN;
                    else
                        [G{y}{m}{c},df2{y}{m}{c}] = fastpiv{m}{c}(M,psi,res);
                    end
                    
                    % Save the unpermuted statistic if not z-score
                    if ~ opts.zstat
                        if p == 1,
                            if opts.saveunivariate,
                                palm_quicksave(G{y}{m}{c},0,opts,plm,y,m,c, ...
                                    sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},ystr{y},mstr{m},cstr{c}));
                                
                                % Save also the degrees of freedom for the unpermuted
                                if numel(df2{y}{m}{c}) == 1,
                                    savedof(plm.rC{m}(c),df2{y}{m}{c}, ...
                                        horzcat(sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},ystr{y},mstr{m},cstr{c}),'_dof.txt'));
                                else
                                    savedof(plm.rC{m}(c),mean(df2{y}{m}{c}), ...
                                        horzcat(sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},ystr{y},mstr{m},cstr{c}),'_meandof.txt'));
                                    palm_quicksave(df2{y}{m}{c},0,opts,plm,y,m,c, ...
                                        horzcat(sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},ystr{y},mstr{m},cstr{c}),'_dof'));
                                end
                            end
                        end
                        
                        % Save the stats for each permutation if that was asked
                        if opts.saveperms && ~ opts.draft,
                            palm_quicksave(G{y}{m}{c},0,opts,plm,y,m,c, ...
                                horzcat(sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},ystr{y},mstr{m},cstr{c}),sprintf('_perm%06d',p)));
                        end
                    end
                    
                    % Convert to Z, but make sure that the rank is changed
                    % just once, regardless
                    if p == 1 && (opts.designperinput || y == 1),
                        plm.rC0{m}(c) = plm.rC{m}(c);
                        plm.rC {m}(c) = 0;
                    end
                    G{y}{m}{c} = palm_gtoz(G{y}{m}{c},plm.rC0{m}(c),df2{y}{m}{c});
                    
                    % Save the unpermuted statistic if z-score
                    if opts.zstat
                        if p == 1,
                            plm.Gname{m}{c} = sprintf('_z%s',plm.Gname{m}{c}(2:end));
                            if opts.saveunivariate,
                                palm_quicksave(G{y}{m}{c},0,opts,plm,y,m,c, ...
                                    sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},ystr{y},mstr{m},cstr{c}));
                            end
                        end
                        
                        % Save the stats for each permutation if that was asked
                        if opts.saveperms && ~ opts.draft,
                            palm_quicksave(G{y}{m}{c},0,opts,plm,y,m,c, ...
                                horzcat(sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},ystr{y},mstr{m},cstr{c}),sprintf('_perm%06d',p)));
                        end
                    end
                    
                    % Remove the sign if this is a two-tailed test. This
                    % makes no difference if rank(C) > 1
                    if opts.twotail && plm.rC0{m}(c) == 1,
                        G{y}{m}{c} = abs(G{y}{m}{c});
                    end
                    
                    % Draft mode
                    if opts.draft,
                        if p == 1,
                            % In the first permutation, keep G and df2,
                            % and start the counter.
                            % In the "draft" mode, the plm.Gpperm variable isn't really a
                            % counter, but the number of permutations performed until
                            % a certain number of exceedances were found.
                            plm.G      {y}{m}{c} = G  {y}{m}{c};
                            plm.df2    {y}{m}{c} = df2{y}{m}{c};
                            plm.Gppermp{y}{m}{c} = zeros(size(G{y}{m}{c}));
                        else
                            % Otherwise, store the permutation in which a larger
                            % statistic happened, and remove this voxel/vertex/face
                            % from further runs.
                            plm.Gpperm{y}{m}{c}(ysel{y}) = plm.Gpperm{y}{m}{c}(ysel{y}) + ...
                                (G{y}{m}{c} >= plm.G{y}{m}{c}(ysel{y}));
                            plm.Gppermp{y}{m}{c}(ysel{y}) = p;
                            ysel{y} = plm.Gpperm{y}{m}{c} < opts.draft;
                        end
                    else
                        if p == 1,
                            % In the first permutation, keep G and df2,
                            % and start the counter.
                            plm.G  {y}{m}{c} = G  {y}{m}{c};
                            plm.df2{y}{m}{c} = df2{y}{m}{c};
                        end
                        plm.Gpperm{y}{m}{c}    = plm.Gpperm{y}{m}{c} + (G{y}{m}{c} >= plm.G{y}{m}{c});
                        plm.Gmax  {y}{m}{c}(p) = max(G{y}{m}{c},[],2);
                        
                        % Cluster extent is here
                        if opts.clustere_uni.do,
                            if p == 1,
                                plm.Gclemax{y}{m}{c} = zeros(plm.nP{m}(c),1);
                                [plm.Gclemax{y}{m}{c}(p),plm.Gcle{y}{m}{c}] = palm_clustere( ...
                                    G{y}{m}{c},y,opts.clustere_uni.thr,opts,plm);
                            else
                                plm.Gclemax{y}{m}{c}(p) = palm_clustere( ...
                                    G{y}{m}{c},y,opts.clustere_uni.thr,opts,plm);
                            end
                        end
                        
                        % Cluster mass is here
                        if opts.clusterm_uni.do,
                            if p == 1,
                                plm.Gclmmax{y}{m}{c} = zeros(plm.nP{m}(c),1);
                                [plm.Gclmmax{y}{m}{c}(p),plm.Gclm{y}{m}{c}] = palm_clusterm( ...
                                    G{y}{m}{c},y,opts.clusterm_uni.thr,opts,plm);
                            else
                                plm.Gclmmax{y}{m}{c}(p) = palm_clusterm( ...
                                    G{y}{m}{c},y,opts.clusterm_uni.thr,opts,plm);
                            end
                        end
                        
                        % TFCE is here
                        if opts.tfce_uni.do,
                            Gtfce{y}{m}{c} = palm_tfce(G{y}{m}{c},y,opts,plm);
                            if p == 1,
                                plm.Gtfcemax  {y}{m}{c} = zeros(plm.nP{m}(c),1);
                                plm.Gtfce     {y}{m}{c} = Gtfce{y}{m}{c};
                                plm.Gtfcepperm{y}{m}{c} = zeros(size(G{y}{m}{c}));
                            end
                            plm.Gtfcepperm{y}{m}{c} = plm.Gtfcepperm{y}{m}{c} + ...
                                (Gtfce{y}{m}{c} >= plm.Gtfce{y}{m}{c});
                            plm.Gtfcemax{y}{m}{c}(p) = max(Gtfce{y}{m}{c},[],2);
                        end
                    end
                end
                
                % NPC for Y only is here
                if opts.npcmod && ~ opts.npccon, % && ~ opts.syncperms,
                    if opts.showprogress,
                        fprintf('\t [Combining modalities]\n');
                    end
                    
                    % Just a feedback message for some situations.
                    if opts.showprogress && ...
                            ~ opts.zstat && ...
                            p == 1 && ...
                            opts.savepara && ...
                            ~ plm.nonpcppara && ...
                            ~ opts.spatial_npc && ...
                            any(strcmpi(opts.npcmethod,{ ...
                            'dudbridge-koeleman', ...
                            'dudbridge-koeleman2'})),
                        fprintf('(1st perm is slower) ');
                    end
                    
                    % Compute the combined statistic
                    for y = 1:plm.nY,
                        Gnpc  {1}(y,:) = G  {y}{m}{c};
                        df2npc{1}(y,:) = df2{y}{m}{c};
                    end
                    if isnichols,
                        [T{m}{c},Gnpcppara] = fastnpc(Gnpc{1},0,df2npc{1});
                    else
                        T{m}{c} = fastnpc(Gnpc{1},0,df2npc{1});
                    end
                    
                    % Since computing the parametric p-value for some methods
                    % can be quite slow, it's faster to run all these checks
                    % to ensure that 'pparanpc' runs just once.
                    if opts.zstat || ...
                            opts.spatial_npc || ...
                            (p == 1 && opts.savepara && ~ plm.nonpcppara),
                        Tppara{m}{c} = pparanpc(T{m}{c});
                        
                        % Reserve the p-parametric to save later.
                        if p == 1,
                            plm.Tppara{m}{c} = Tppara{m}{c};
                        end
                    end
                    
                    % Convert T to zstat if that was asked (note that at this point,
                    % G was already converted to z before making T).
                    if opts.zstat,
                        T{m}{c} = -erfinv(2*Tppara{m}{c}-1)*sqrt(2);
                        if p == 1,
                            plm.npcstr = horzcat('_z',plm.npcstr(2:end));
                        end
                    end
                    
                    % Save the NPC Statistic (this is inside the loop because
                    % of the two-tailed option)
                    if p == 1,
                        palm_quicksave(T{m}{c},0,opts,plm,[],m,c, ...
                            sprintf('%s',opts.o,plm.Ykindstr{1},plm.npcstr,plm.Tname,mstr{m},cstr{c}));
                    end
                    
                    % If the user wants to save the NPC statistic for each
                    % permutation, save it now.
                    if opts.saveperms,
                        palm_quicksave(T{m}{c},0,opts,plm,[],m,c, ...
                            horzcat(sprintf('%s',opts.o,plm.Ykindstr{1},plm.npcstr,plm.Tname,mstr{m},cstr{c}),sprintf('_perm%06d',p)));
                    end
                    
                    % Increment counters
                    if p == 1,
                        plm.T{m}{c} = T{m}{c};
                        plm.Tpperm{m}{c} = zeros(size(T{m}{c}));
                    end
                    if isnichols,
                        plm.Tpperm{m}{c} = plm.Tpperm{m}{c} + ...
                            sum(bsxfun(npcrel,Gnpc{1},plm.T{m}{c}),1);
                        plm.Tmax{m}{c}(p,:) = npcextr(Gnpcppara,[],2)';
                    else
                        plm.Tpperm{m}{c} = plm.Tpperm{m}{c} + ...
                            bsxfun(npcrel,T{m}{c},plm.T{m}{c});
                        plm.Tmax{m}{c}(p) = npcextr(T{m}{c},[],2);
                    end
                    
                    % Be sure to use z-scores for the spatial statistics, converting
                    % it if not already.
                    if opts.spatial_npc,
                        if ~ opts.zstat,
                            T{m}{c} = -erfinv(2*Tppara{m}{c}-1)*sqrt(2);
                        end
                    end
                    
                    % Cluster extent NPC is here
                    if opts.clustere_npc.do,
                        if p == 1,
                            [plm.Tclemax{m}{c}(p),plm.Tcle{m}{c}] = ...
                                palm_clustere(T{m}{c},1,opts.clustere_npc.thr,opts,plm);
                        else
                            plm.Tclemax{m}{c}(p) = ...
                                palm_clustere(T{m}{c},1,opts.clustere_npc.thr,opts,plm);
                        end
                    end
                    
                    % Cluster mass NPC is here
                    if opts.clusterm_npc.do,
                        if p == 1,
                            [plm.Tclmmax{m}{c}(p),plm.Tclm{m}{c}] = ...
                                palm_clusterm(T{m}{c},1,opts.clusterm_npc.thr,opts,plm);
                        else
                            plm.Tclmmax{m}{c}(p) = ...
                                palm_clusterm(T{m}{c},1,opts.clusterm_npc.thr,opts,plm);
                        end
                    end
                    
                    % TFCE NPC is here
                    if opts.tfce_npc.do,
                        Ttfce{m}{c} = palm_tfce(T{m}{c},1,opts,plm);
                        if p == 1,
                            plm.Ttfcemax  {m}{c} = zeros(plm.nP{m}(c),1);
                            plm.Ttfce     {m}{c} = Ttfce{m}{c};
                            plm.Ttfcepperm{m}{c} = zeros(size(T{m}{c}));
                        end
                        plm.Ttfcepperm{m}{c} = plm.Ttfcepperm{m}{c} + ...
                            (Ttfce{m}{c} >= plm.Ttfce{m}{c});
                        plm.Ttfcemax{m}{c}(p) = max(Ttfce{m}{c},[],2);
                    end
                end
                
                % MANOVA/MANCOVA is here
                if opts.MV,
                    if opts.showprogress,
                        fprintf('\t [Doing multivariate analysis]\n');
                    end
                    
                    % Shuffle the data and/or design.
                    if opts.draft,
                        if p == 1,
                            yselq = true(1,size(plm.Yq{m}{c},2),1);
                        end
                        for y = 1:plm.nY,
                            [M,Y] = prepglm{m}{c}(plm.Pset{p},plm.Yq{m}{c}(:,yselq,y));
                            psiq(:,:,y) = M\Y(:,:,y);
                            resq(:,:,y) = Y(:,:,y) - M*psiq(:,:,y);
                        end
                    end
                    
                    % ter Braak permutes under alternative.
                    if isterbraak,
                        if p == 1,
                            psiq0 = psiq;
                        else
                            psiq  = psiq - psiq0;
                        end
                    end
                    
                    % Compute the pivotal multivariate statistic.
                    Q{m}{c} = fastmv{m}{c}(M,psiq,resq);
                    
                    % Since computing the parametric p-value for some methods
                    % can be quite slow, it's faster to run all these checks
                    % to ensure that 'pparamv' runs just once.
                    if opts.zstat            || ...
                            opts.spatial_mv  || ...
                            (p == 1          && ...
                            opts.savepara    && ...
                            ~ plm.nomvppara),
                        Qppara{m}{c} = pparamv(Q{m}{c});
                        
                        % Reserve the p-parametric to save later.
                        if p == 1,
                            plm.Qppara{m}{c} = Qppara{m}{c};
                        end
                    end
                    
                    % Convert to zstat if that was asked
                    if opts.zstat,
                        Q{m}{c} = -erfinv(2*Qppara{m}{c}-1)*sqrt(2);
                        if p == 1,
                            plm.mvstr = horzcat('_z',plm.mvstr(2:end));
                        end
                    end
                    
                    % Save the MV statistic
                    if p == 1,
                        palm_quicksave(Q{m}{c},0,opts,plm,[],m,c, ...
                            sprintf('%s',opts.o,plm.Ykindstr{1},plm.mvstr,plm.Qname{m}{c},mstr{m},cstr{c}));
                    end
                    
                    % In the "draft" mode, the plm.Qpperm variable isn't a counter,
                    % but the number of permutations until a statistic larger than
                    % the unpermuted was found.
                    if opts.draft,
                        if p == 1,
                            % In the first permutation, keep Q and Qdf2,
                            % and start the counter.
                            plm.Q      {m}{c} = Q{m}{c};
                            plm.Qdf2   {m}{c} = Qdf2{m}{c};
                            plm.Qpperm {m}{c} = zeros(size(Q{m}{c}));
                            plm.Qppermp{m}{c} = zeros(size(Q{m}{c}));
                            
                        else
                            % Otherwise, store the permutation in which a larger
                            % statistic happened, and remove this voxel/vertex/face
                            % from further runs.
                            plm.Qpperm{m}{c}(yselq) = plm.Qpperm{m}{c}(yselq) + ...
                                (Q{m}{c} >= plm.Q{m}{c}(yselq));
                            plm.Qppermp{m}{c}(yselq) = p;
                            yselq = plm.Qpperm{m}{c} < opts.draft;
                        end
                    else
                        
                        % If the user wants to save the statistic for each
                        % permutation, save it now. This isn't obviously allowed
                        % in draft mode, as the images are not complete. Also,
                        % this is inside the loop to allow the two-tailed option
                        % not to use to much memory
                        if opts.saveperms,
                            palm_quicksave(Q{m}{c},0,opts,plm,[],m,c, ...
                                horzcat(sprintf('%s',opts.o,plm.Ykindstr{1},plm.mvstr,plm.Qname{m}{c},mstr{m},cstr{c}),sprintf('_perm%06d',p)));
                        end
                        if p == 1,
                            % In the first permutation, keep Q and start the counter.
                            plm.Q     {m}{c} = Q{m}{c};
                            plm.Qpperm{m}{c} = zeros(size(Q{m}{c}));
                        end
                        plm.Qpperm{m}{c}     = plm.Qpperm{m}{c} + (Q{m}{c} >= plm.Q{m}{c});
                        plm.Qmax  {m}{c}(p)  = max(Q{m}{c},[],2);
                        
                        % Now compute the spatial statistics, converting to z-score
                        % if not already.
                        if opts.spatial_mv,
                            if ~ opts.zstat,
                                Q{m}{c} = -erfinv(2*Qppara{m}{c}-1)*sqrt(2);
                            end
                        end
                        
                        % Cluster extent is here
                        if opts.clustere_mv.do,
                            if p == 1,
                                [plm.Qclemax{m}{c}(p),plm.Qcle{m}{c}] = ...
                                    palm_clustere(Q{m}{c},1,opts.clustere_mv.thr,opts,plm);
                            else
                                plm.Qclemax{m}{c}(p) = ...
                                    palm_clustere(Q{m}{c},1,opts.clustere_mv.thr,opts,plm);
                            end
                        end
                        
                        % Cluster mass is here
                        if opts.clusterm_mv.do,
                            if p == 1,
                                [plm.Qclmmax{m}{c}(p),plm.Qclm{m}{c}] = ...
                                    palm_clusterm(Q{m}{c},1,opts.clusterm_mv.thr,opts,plm);
                            else
                                plm.Qclmmax{m}{c}(p) = ...
                                    palm_clusterm(Q{m}{c},1,opts.clusterm_mv.thr,opts,plm);
                            end
                        end
                        
                        % TFCE is here
                        if opts.tfce_mv.do,
                            Qtfce{m}{c} = palm_tfce(Q{m}{c},1,opts,plm);
                            if p == 1,
                                plm.Qtfce     {m}{c} = Qtfce{m}{c};
                                plm.Qtfcepperm{m}{c} = zeros(size(Q{m}{c}));
                            end
                            plm.Qtfcepperm{m}{c} = plm.Qtfcepperm{m}{c} + ...
                                (Qtfce{m}{c} >= plm.Qtfce{m}{c});
                            plm.Qtfcemax{m}{c}(p) = max(Qtfce{m}{c},[],2);
                        end
                    end
                    
                elseif opts.CCA,
                    if opts.showprogress,
                        fprintf('\t [Doing CCA]\n');
                    end
                    
                    if opts.draft && p == 1,
                        yselq = true(1,1,size(plm.Yq{m}{c},3));
                    end
                    
                    % Compute the CC coefficient
                    if p == 1,
                        Q{m}{c} = zeros(1,plm.Ysiz(1));
                    end
                    M = plm.Pset{p}*plm.Rz{m}{c}*plm.X{m}{c};
                    for t = find(ysel)',
                        Q{m}{c}(t) = cca(plm.Yq{m}{c}(:,:,t),M,opts.ccaparm);
                    end
                    
                    % Convert to zstat if that was asked
                    if opts.zstat,
                        Q{m}{c} = atanh(Q{m}{c});
                        if p == 1,
                            plm.mvstr = horzcat('_z',plm.mvstr(2:end));
                        end
                    end
                    
                    % Save the CCA statistic
                    if p == 1,
                        palm_quicksave(Q{m}{c},0,opts,plm,[],m,c, ...
                            sprintf('%s',opts.o,plm.Ykindstr{1},plm.mvstr,plm.Qname{m}{c},mstr{m},cstr{c}));
                    end
                    
                    % In the "draft" mode, the plm.Qpperm variable isn't a counter,
                    % but the number of permutations until a statistic larger than
                    % the unpermuted was found.
                    if opts.draft,
                        if p == 1,
                            % In the first permutation, keep Q and Qdf2,
                            % and start the counter.
                            plm.Q      {m}{c} = Q{m}{c};
                            plm.Qpperm {m}{c} = zeros(size(Q{m}{c}));
                            plm.Qppermp{m}{c} = zeros(size(Q{m}{c}));
                            
                        else
                            % Otherwise, store the permutation in which a larger
                            % statistic happened, and remove this voxel/vertex/face
                            % from further runs.
                            plm.Qpperm{m}{c}(yselq) = plm.Qpperm{m}{c}(yselq) + ...
                                (Q{m}{c} >= plm.Q{m}{c}(yselq));
                            plm.Qppermp{m}{c}(yselq) = p;
                            yselq = plm.Qpperm{m}{c} < opts.draft;
                        end
                    else
                        
                        % If the user wants to save the statistic for each
                        % permutation, save it now. This isn't obviously allowed
                        % in draft mode, as the images are not complete. Also,
                        % this is inside the loop to allow the two-tailed option
                        % not to use to much memory
                        if opts.saveperms,
                            palm_quicksave(Q{m}{c},0,opts,plm,[],m,c, ...
                                horzcat(sprintf('%s',opts.o,plm.Ykindstr{1},plm.mvstr,plm.Qname{m}{c},mstr{m},cstr{c}),sprintf('_perm%06d',p)));
                        end
                        if p == 1,
                            % In the first permutation, keep Q and start the counter.
                            plm.Q     {m}{c} = Q{m}{c};
                            plm.Qpperm{m}{c} = zeros(size(Q{m}{c}));
                        end
                        plm.Qpperm{m}{c}     = plm.Qpperm{m}{c} + (Q{m}{c} >= plm.Q{m}{c});
                        plm.Qmax  {m}{c}(p)  = max(Q{m}{c},[],2);
                        
                        % Now compute the MV spatial statistics, converting to z-score
                        % if not already.
                        if opts.spatial_mv,
                            if ~ opts.zstat,
                                Q{m}{c} = atanh(Q{m}{c});
                            end
                        end
                        
                        % Cluster extent is here
                        if opts.clustere_mv.do,
                            if p == 1,
                                [plm.Qclemax{m}{c}(p),plm.Qcle{m}{c}] = ...
                                    palm_clustere(Q{m}{c},1,opts.clustere_mv.thr,opts,plm);
                            else
                                plm.Qclemax{m}{c}(p) = ...
                                    palm_clustere(Q{m}{c},1,opts.clustere_mv.thr,opts,plm);
                            end
                        end
                        
                        % Cluster mass is here
                        if opts.clusterm_mv.do,
                            if p == 1,
                                [plm.Qclmmax{m}{c}(p),plm.Qclm{m}{c}] = ...
                                    palm_clusterm(Q{m}{c},1,opts.clusterm_mv.thr,opts,plm);
                            else
                                plm.Qclmmax{m}{c}(p) = ...
                                    palm_clusterm(Q{m}{c},1,opts.clusterm_mv.thr,opts,plm);
                            end
                        end
                        
                        % TFCE is here
                        if opts.tfce_mv.do,
                            Qtfce{m}{c} = palm_tfce(Q{m}{c},1,opts,plm);
                            if p == 1,
                                plm.Qtfce     {m}{c} = Qtfce{m}{c};
                                plm.Qtfcepperm{m}{c} = zeros(size(Q{m}{c}));
                            end
                            plm.Qtfcepperm{m}{c} = plm.Qtfcepperm{m}{c} + ...
                                (Qtfce{m}{c} >= plm.Qtfce{m}{c});
                            plm.Qtfcemax{m}{c}(p) = max(Qtfce{m}{c},[],2);
                        end
                    end
                end
            end
            if ~ opts.syncperms,
                ProgressCon = ProgressCon + 1;
            end
        end
    end
    
    % NPC for contrasts is here
    if opts.npccon,
        
        % Just a feedback message for some situations.
        if opts.showprogress && ...
                ~ opts.zstat && ...
                po == 1 && ...
                opts.savepara && ...
                ~ plm.nonpcppara && ...
                ~ opts.spatial_npc && ...
                any(strcmpi(opts.npcmethod,{ ...
                'dudbridge-koeleman', ...
                'dudbridge-koeleman2'})),
            fprintf('(1st perm is slower) ');
        end
        
        % Assemble the stats for the combination
        if opts.npcmod,
            if opts.showprogress,
                fprintf('\t [Combining modalities and contrasts]\n');
            end
            j = 1;
            for y = 1:plm.nY,
                if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
                for m = loopM,
                    for c = 1:plm.nC(m),
                        Gnpc  {1}(j,:) = G  {y}{m}{c};
                        df2npc{1}(j,:) = df2{y}{m}{c};
                        j = j + 1;
                    end
                end
            end
            if isnichols,
                plm.Tmax{1} = zeros(plm.nP{1}(1),plm.nY);
            else
                plm.Tmax{1} = zeros(plm.nP{1}(1),1);
            end
        else
            if opts.showprogress,
                fprintf('\t [Combining contrasts]\n');
            end
            for y = 1:plm.nY,
                j = 1;
                if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
                for m = loopM,
                    for c = 1:plm.nC(m),
                        Gnpc  {y}(j,:) = G  {y}{m}{c};
                        df2npc{y}(j,:) = df2{y}{m}{c};
                        j = j + 1;
                    end
                end
                if isnichols,
                    plm.Tmax{y} = zeros(plm.nP{1}(1),sum(plm.nC));
                else
                    plm.Tmax{y} = zeros(plm.nP{1}(1),1);
                end
            end
            
        end
        
        % For each of set to be combined
        jstr = cell(numel(Gnpc),1);
        for j = 1:numel(Gnpc),
            
            % String with the counter
            if po == 1
                if ~ opts.npcmod && (plm.nY > 1 || opts.verbosefilenames),
                    jstr{j} = sprintf('_m%d',j);
                else
                    jstr{j} = '';
                end
            end
            
            % Compute the combined statistic
            if isnichols,
                [T{j},Gnpcppara] = fastnpc(Gnpc{j},0,df2npc{j});
            else
                T{j} = fastnpc(Gnpc{j},0,df2npc{j});
            end
            
            % Since computing the parametric p-value for some methods
            % can be quite slow, it's faster to run all these checks
            % to ensure that 'pparanpc' runs just once.
            if opts.zstat || ...
                    opts.spatial_npc || ...
                    (po == 1 && opts.savepara && ~ plm.nonpcppara),
                Tppara{j} = pparanpc(T{j});
                
                % Reserve the p-parametric to save later.
                if po == 1,
                    plm.Tppara{j} = Tppara{j};
                end
            end
            
            % Convert T to zstat if that was asked (note that at this point,
            % G was already converted to z before making T).
            if opts.zstat,
                T{j} = -erfinv(2*Tppara{j}-1)*sqrt(2);
                if po == 1,
                    plm.npcstr = horzcat('_z',plm.npcstr(2:end));
                end
            end
            
            % Save the NPC Statistic (this is inside the loop because
            % of the two-tailed option)
            if po == 1,
                palm_quicksave(T{j},0,opts,plm,j,[],[], ...
                    sprintf('%s',opts.o,plm.Ykindstr{j},plm.npcstr,plm.Tname,jstr{j}));
            end
            
            % If the user wants to save the NPC statistic for each
            % permutation, save it now.
            if opts.saveperms,
                palm_quicksave(T{j},0,opts,plm,j,[],[], ...
                    horzcat(sprintf('%s',opts.o,plm.Ykindstr{j},plm.npcstr,plm.Tname,jstr{j}),sprintf('_perm%06d',po)));
            end
            
            % Increment counters
            if po == 1,
                plm.T{j} = T{j};
                plm.Tpperm{j} = zeros(size(T{j}));
            end
            if isnichols,
                plm.Tpperm{j} = plm.Tpperm{j} + ...
                    sum(bsxfun(npcrel,Gnpc{j},plm.T{j}),1);
                plm.Tmax{j}(po,:) = npcextr(Gnpcppara,[],2)';
            else
                plm.Tpperm{j} = plm.Tpperm{j} + ...
                    bsxfun(npcrel,T{j},plm.T{j});
                plm.Tmax{j}(po) = npcextr(T{j},[],2);
            end
            
            % Be sure to use z-scores for the spatial statistics, converting
            % it if not already.
            if opts.spatial_npc,
                if ~ opts.zstat,
                    T{j} = -erfinv(2*Tppara{j}-1)*sqrt(2);
                end
            end
            
            % Cluster extent NPC is here
            if opts.clustere_npc.do,
                if p == 1,
                    [plm.Tclemax{j}(po),plm.Tcle{j}] = ...
                        palm_clustere(T{j},1,opts.clustere_npc.thr,opts,plm);
                else
                    plm.Tclemax{j}(po) = ...
                        palm_clustere(T{j},1,opts.clustere_npc.thr,opts,plm);
                end
            end
            
            % Cluster mass NPC is here
            if opts.clusterm_npc.do,
                if p == 1,
                    [plm.Tclmmax{j}(po),plm.Tclm{j}] = ...
                        palm_clusterm(T{j},1,opts.clusterm_npc.thr,opts,plm);
                else
                    plm.Tclmmax{j}(po) = ...
                        palm_clusterm(T{j},1,opts.clusterm_npc.thr,opts,plm);
                end
            end
            
            % TFCE NPC is here
            if opts.tfce_npc.do,
                Ttfce{j} = palm_tfce(T{j},1,opts,plm);
                if p == 1,
                    plm.Ttfcemax  {j} = zeros(plm.nP{1}(1),1);
                    plm.Ttfce     {j} = Ttfce{j};
                    plm.Ttfcepperm{j} = zeros(size(T{j}));
                end
                plm.Ttfcepperm{j} = plm.Ttfcepperm{j} + ...
                    (Ttfce{j} >= plm.Ttfce{j});
                plm.Ttfcemax{j}(po) = max(Ttfce{j},[],2);
            end
        end
    end
end

% Free up a bit of memory after the loop.
clear M Y psi res G df2 T Q;

% ==============================================================
% Generate and save the p-values:
% ==============================================================

fprintf('Computing p-values.\n');
% Start with the uncorrected, but don't save them yet.
% They'll be used later for the FDR.
for y = 1:plm.nY,
    if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
    for m = loopM,
        for c = 1:plm.nC(m),
            if opts.draft,
                plm.Gpperm{y}{m}{c} = (plm.Gpperm{y}{m}{c} + 1)./plm.Gppermp{y}{m}{c};
            else
                plm.Gpperm{y}{m}{c} = plm.Gpperm{y}{m}{c}/plm.nP{m}(c);
                if opts.tfce_uni.do,
                    plm.Gtfcepperm{y}{m}{c} = plm.Gtfcepperm{y}{m}{c}/plm.nP{m}(c);
                end
            end
        end
    end
end
if opts.NPC,
    if opts.npcmod && ~ opts.npccon,
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                if isnichols,
                    plm.Tmax{m}{c} = plm.Tmax{m}{c}(:);
                end
                plm.Tpperm{m}{c} = plm.Tpperm{m}{c}/numel(plm.Tmax{m}{c});
                if opts.tfce_npc.do,
                    plm.Ttfcepperm{m}{c} = plm.Ttfcepperm{m}{c}/plm.nP{m}(c);
                end
            end
        end
    elseif opts.npccon,
        for j = 1:numel(plm.Tmax),
            if isnichols,
                plm.Tmax{j} = plm.Tmax{j}(:);
            end
            plm.Tpperm{j} = plm.Tpperm{j}/numel(plm.Tmax{j});
            if opts.tfce_npc.do,
                plm.Ttfcepperm{j} = plm.Ttfcepperm{j}/numel(plm.Tmax{j});
            end
        end
    end
end
if opts.MV || opts.CCA,
    for m = 1:plm.nM,
        for c = 1:plm.nC(m),
            if opts.draft,
                plm.Qpperm{m}{c} = (plm.Qpperm{m}{c} + 1)./plm.Qppermp{m}{c};
            else
                plm.Qpperm{m}{c} = plm.Qpperm{m}{c}/plm.nP{m}(c);
            end
            if opts.tfce_mv.do,
                plm.Qtfcepperm{m}{c} = plm.Qtfcepperm{m}{c}/plm.nP{m}(c);
            end
        end
    end
end

% Save uncorrected & FWER-corrected within modality for this contrast.
if opts.saveunivariate,
    fprintf('Saving p-values (uncorrected, and corrected within modality and within contrast).\n');
    for y = 1:plm.nY,
        if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
        for m = loopM,
            for c = 1:plm.nC(m),
                
                % Only permutation p-value and its FDR ajustment are saved in the draft mode.
                if opts.draft,
                    
                    % Permutation p-value, uncorrected
                    palm_quicksave(plm.Gpperm{y}{m}{c},1,opts,plm,y,m,c, ...
                        sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},'_uncp',ystr{y},mstr{m},cstr{c}));
                    
                    % Permutation p-value, FDR adjusted
                    if opts.FDR,
                        palm_quicksave(fastfdr(plm.Gpperm{y}{m}{c}),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},'_fdrp',ystr{y},mstr{m},cstr{c}));
                    end
                else
                    
                    % Permutation p-value
                    palm_quicksave(plm.Gpperm{y}{m}{c},1,opts,plm,y,m,c, ...
                        sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},'_uncp',ystr{y},mstr{m},cstr{c}));
                    
                    % FWER-corrected
                    palm_quicksave( ...
                        palm_datapval(plm.G{y}{m}{c},plm.Gmax{y}{m}{c},false),1,opts,plm,y,m,c,...
                        sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},'_fwep',ystr{y},mstr{m},cstr{c}));
                    
                    % Permutation p-value, FDR adjusted
                    if opts.FDR,
                        palm_quicksave(fastfdr(plm.Gpperm{y}{m}{c}),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},'_fdrp',ystr{y},mstr{m},cstr{c}));
                    end
                    
                    % Cluster extent results.
                    if opts.clustere_uni.do,
                        
                        % Cluster extent statistic.
                        palm_quicksave(plm.Gcle{y}{m}{c},0,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,'_clustere',plm.Gname{m}{c},ystr{y},mstr{m},cstr{c}));
                        
                        % Cluster extent FWER p-value
                        palm_quicksave( ...
                            palm_datapval(plm.Gcle{y}{m}{c},plm.Gclemax{y}{m}{c},false),1,opts,plm,y,m,c,...
                            sprintf('%s',opts.o,'_clustere',plm.Gname{m}{c},'_fwep',ystr{y},mstr{m},cstr{c}));
                    end
                    
                    % Cluster mass results.
                    if opts.clusterm_uni.do,
                        
                        % Cluster mass statistic.
                        palm_quicksave(plm.Gclm{y}{m}{c},0,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,'_clusterm',plm.Gname{m}{c},ystr{y},mstr{m},cstr{c}));
                        
                        % Cluster mass FWER p-value.
                        palm_quicksave( ...
                            palm_datapval(plm.Gclm{y}{m}{c},plm.Gclmmax{y}{m}{c},false),1,opts,plm,y,m,c,...
                            sprintf('%s',opts.o,'_clusterm',plm.Gname{m}{c},'_fwep',ystr{y},mstr{m},cstr{c}));
                    end
                    
                    % TFCE results
                    if opts.tfce_uni.do,
                        
                        % TFCE statistic
                        palm_quicksave(plm.Gtfce{y}{m}{c},0,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,'_tfce',plm.Gname{m}{c},ystr{y},mstr{m},cstr{c}));
                        
                        % TFCE p-value
                        palm_quicksave(plm.Gtfcepperm{y}{m}{c},1,opts,plm,y,m,c,...
                            sprintf('%s',opts.o,'_tfce',plm.Gname{m}{c},'_uncp',ystr{y},mstr{m},cstr{c}));
                        
                        % TFCE FWER-corrected within modality and contrast.
                        palm_quicksave( ...
                            palm_datapval(plm.Gtfce{y}{m}{c},plm.Gtfcemax{y}{m}{c},false),1,opts,plm,y,m,c,...
                            sprintf('%s',opts.o,'_tfce',plm.Gname{m}{c},'_fwep',ystr{y},mstr{m},cstr{c}));
                        
                        % TFCE p-value, FDR adjusted.
                        if opts.FDR,
                            palm_quicksave(fastfdr(plm.Gtfcepperm{y}{m}{c}),1,opts,plm,y,m,c, ...
                                sprintf('%s',opts.o,'_tfce',plm.Gname{m}{c},'_fdrp',ystr{y},mstr{m},cstr{c}));
                        end
                    end
                end
                
                % Parametric p-value and its FDR adjustment
                if opts.savepara,
                    P = palm_quicksave(plm.G{y}{m}{c},2,opts,plm,y,m,c,...
                        sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},'_uncparap',ystr{y},mstr{m},cstr{c}));
                    if opts.FDR,
                        palm_quicksave(fastfdr(P),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},'_fdrparap',ystr{y},mstr{m},cstr{c}));
                    end
                end
            end
        end
    end
    
    % Save FWER & FDR corrected across modalities.
    if opts.corrmod,
        fprintf('Saving p-values (corrected across modalities).\n')
        
        % FWER correction (non-spatial stats)
        if opts.designperinput,
            for c = 1:plm.nC(1),
                distmax = zeros(plm.nP{1}(c),plm.nY);
                for y = 1:plm.nY,
                    m = y;
                    distmax(:,y) = plm.Gmax{y}{m}{c};
                end
                distmax = max(distmax,[],2);
                for y = 1:plm.nY,
                    m = y;
                    palm_quicksave( ...
                        palm_datapval(plm.G{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                        sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},'_mfwep',ystr{y},mstr{m},cstr{c}));
                end
            end
        else
            for m = 1:plm.nM,
                for c = 1:plm.nC(m),
                    distmax = zeros(plm.nP{m}(c),plm.nY);
                    for y = 1:plm.nY,
                        distmax(:,y) = plm.Gmax{y}{m}{c};
                    end
                    distmax = max(distmax,[],2);
                    for y = 1:plm.nY,
                        palm_quicksave( ...
                            palm_datapval(plm.G{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},'_mfwep',ystr{y},mstr{m},cstr{c}));
                    end
                end
            end
        end
        
        % FDR correction (non-spatial stats)
        if opts.FDR,
            if opts.designperinput,
                for c = 1:plm.nC(1),
                    pmerged = zeros(sum(plm.Ysiz),1);
                    for y = 1:plm.nY,
                        m = y;
                        pmerged(plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)) = plm.Gpperm{y}{m}{c};
                    end
                    pfdradj = fastfdr(pmerged);
                    for y = 1:plm.nY,
                        m = y;
                        palm_quicksave(pfdradj(plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},'_mfdrp',ystr{y},mstr{m},cstr{c}));
                    end
                end
            else
                for m = 1:plm.nM,
                    for c = 1:plm.nC(m),
                        pmerged = zeros(sum(plm.Ysiz),1);
                        for y = 1:plm.nY,
                            pmerged(plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)) = plm.Gpperm{y}{m}{c};
                        end
                        pfdradj = fastfdr(pmerged);
                        for y = 1:plm.nY,
                            palm_quicksave(pfdradj(plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)),1,opts,plm,y,m,c, ...
                                sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},'_mfdrp',ystr{y},mstr{m},cstr{c}));
                        end
                    end
                end
            end
        end
        
        % Cluster extent
        if opts.clustere_uni.do && ...
                (all(plm.Yisvol) || all(plm.Yissrf)),
            if opts.designperinput,
                for c = 1:plm.nC(1),
                    distmax = zeros(plm.nP{1}(c),plm.nY);
                    for y = 1:plm.nY,
                        m = y;
                        distmax(:,y) = plm.Gclemax{y}{m}{c};
                    end
                    distmax = max(distmax,[],2);
                    for y = 1:plm.nY,
                        m = y;
                        palm_quicksave( ...
                            palm_datapval(plm.Gcle{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,'_clustere',plm.Gname{m}{c},'_mfwep',ystr{y},mstr{m},cstr{c}));
                    end
                end
            else
                for m = 1:plm.nM,
                    for c = 1:plm.nC(m),
                        distmax = zeros(plm.nP{m}(c),plm.nY);
                        for y = 1:plm.nY,
                            distmax(:,y) = plm.Gclemax{y}{m}{c};
                        end
                        distmax = max(distmax,[],2);
                        for y = 1:plm.nY,
                            palm_quicksave( ...
                                palm_datapval(plm.Gcle{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                                sprintf('%s',opts.o,'_clustere',plm.Gname{m}{c},'_mfwep',ystr{y},mstr{m},cstr{c}));
                        end
                    end
                end
            end
        end
        
        % Cluster mass
        if opts.clusterm_uni.do && ...
                (all(plm.Yisvol) || all(plm.Yissrf)),
            if opts.designperinput,
                for c = 1:plm.nC(1),
                    distmax = zeros(plm.nP{1}(c),plm.nY);
                    for y = 1:plm.nY,
                        m = y;
                        distmax(:,y) = plm.Gclmmax{y}{m}{c};
                    end
                    distmax = max(distmax,[],2);
                    for y = 1:plm.nY,
                        m = y;
                        palm_quicksave( ...
                            palm_datapval(plm.Gclm{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,'_clusterm',plm.Gname{m}{c},'_mfwep',ystr{y},mstr{m},cstr{c}));
                    end
                end
            else
                for m = 1:plm.nM,
                    for c = 1:plm.nC(m),
                        distmax = zeros(plm.nP{m}(c),plm.nY);
                        for y = 1:plm.nY,
                            distmax(:,y) = plm.Gclmmax{y}{m}{c};
                        end
                        distmax = max(distmax,[],2);
                        for y = 1:plm.nY,
                            palm_quicksave( ...
                                palm_datapval(plm.Gclm{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                                sprintf('%s',opts.o,'_clusterm',plm.Gname{m}{c},'_mfwep',ystr{y},mstr{m},cstr{c}));
                        end
                    end
                end
            end
        end
        
        % TFCE
        if opts.tfce_uni.do && ...
                (all(plm.Yisvol) || all(plm.Yissrf)),
            if opts.designperinput,
                for c = 1:plm.nC(1),
                    distmax = zeros(plm.nP{1}(c),plm.nY);
                    for y = 1:plm.nY,
                        m = y;
                        distmax(:,y) = plm.Gtfcemax{y}{m}{c};
                    end
                    distmax = max(distmax,[],2);
                    for y = 1:plm.nY,
                        m = y;
                        palm_quicksave( ...
                            palm_datapval(plm.Gtfce{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,'_tfce',plm.Gname{m}{c},'_mfwep',ystr{y},mstr{m},cstr{c}));
                    end
                end
            else
                for m = 1:plm.nM,
                    for c = 1:plm.nC(m),
                        distmax = zeros(plm.nP{m}(c),plm.nY);
                        for y = 1:plm.nY,
                            distmax(:,y) = plm.Gtfcemax{y}{m}{c};
                        end
                        distmax = max(distmax,[],2);
                        for y = 1:plm.nY,
                            palm_quicksave( ...
                                palm_datapval(plm.Gtfce{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                                sprintf('%s',opts.o,'_tfce',plm.Gname{m}{c},'_mfwep',ystr{y},mstr{m},cstr{c}));
                        end
                    end
                end
            end
            if opts.FDR,
                if opts.designperinput,
                    for c = 1:plm.nC(1),
                        pmerged = zeros(sum(plm.Ysiz),1);
                        for y = 1:plm.nY,
                            m = y;
                            pmerged(plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)) = plm.Gtfcepperm{y}{m}{c};
                        end
                        pfdradj = fastfdr(pmerged);
                        for y = 1:plm.nY,
                            m = y;
                            palm_quicksave(pfdradj(plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)),1,opts,plm,y,m,c, ...
                                sprintf('%s',opts.o,'_tfce',plm.Gname{m}{c},'_mfdrp',ystr{y},mstr{m},cstr{c}));
                        end
                    end
                else
                    for m = 1:plm.nM,
                        for c = 1:plm.nC(m),
                            pmerged = zeros(sum(plm.Ysiz),1);
                            for y = 1:plm.nY,
                                pmerged(plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)) = plm.Gtfcepperm{y}{m}{c};
                            end
                            pfdradj = fastfdr(pmerged);
                            for y = 1:plm.nY,
                                palm_quicksave(pfdradj(plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)),1,opts,plm,y,m,c, ...
                                    sprintf('%s',opts.o,'_tfce',plm.Gname{m}{c},'_mfdrp',ystr{y},mstr{m},cstr{c}));
                            end
                        end
                    end
                end
            end
        end
    end
    
    % Save FWER & FDR corrected across contrasts.
    if opts.corrcon,
        fprintf('Saving p-values (corrected across contrasts).\n');
        
        % FWER correction (non-spatial stats)
        for y = 1:plm.nY,
            if opts.designperinput,
                loopM = y;
                distmax = zeros(plm.nP{1}(1),plm.nC(1));
            else
                loopM = 1:plm.nM;
                distmax = zeros(plm.nP{1}(1),sum(plm.nC));
            end
            j = 1;
            for m = loopM,
                for c = 1:plm.nC(m),
                    distmax(:,j) = plm.Gmax{y}{m}{c};
                    j = j + 1;
                end
            end
            distmax = max(distmax,[],2);
            for m = loopM,
                for c = 1:plm.nC(m),
                    palm_quicksave( ...
                        palm_datapval(plm.G{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                        sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},'_cfwep',ystr{y},mstr{m},cstr{c}));
                end
            end
        end
        
        % FDR correction (non-spatial stats)
        if opts.FDR,
            for y = 1:plm.nY,
                if opts.designperinput,
                    loopM = y;
                    pmerged = zeros(plm.nC(1),plm.Ysiz(y));
                else
                    loopM = 1:plm.nM;
                    pmerged = zeros(sum(plm.nC),plm.Ysiz(y));
                end
                j = 1;
                for m = loopM,
                    for c = 1:plm.nC(m),
                        pmerged(j,:) = plm.Gpperm{y}{m}{c};
                        j = j + 1;
                    end
                end
                pfdradj = reshape(fastfdr(pmerged(:)),size(pmerged));
                j = 1;
                for m = loopM,
                    for c = 1:plm.nC(m),
                        palm_quicksave(pfdradj(j,:),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},'_cfdrp',ystr{y},mstr{m},cstr{c}));
                        j = j + 1;
                    end
                end
            end
        end
        
        % Cluster extent
        if opts.clustere_uni.do,
            for y = 1:plm.nY,
                if opts.designperinput,
                    loopM = y;
                    distmax = zeros(plm.nP{1}(1),plm.nC(1));
                else
                    loopM = 1:plm.nM;
                    distmax = zeros(plm.nP{1}(1),sum(plm.nC));
                end
                j = 1;
                for m = loopM,
                    for c = 1:plm.nC(m),
                        distmax(:,j) = plm.Gclemax{y}{m}{c};
                        j = j + 1;
                    end
                end
                distmax = max(distmax,[],2);
                for m = loopM,
                    for c = 1:plm.nC(m),
                        palm_quicksave( ...
                            palm_datapval(plm.Gcle{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,'_clustere',plm.Gname{m}{c},'_cfwep',ystr{y},mstr{m},cstr{c}));
                    end
                end
            end
        end
        
        % Cluster mass
        if opts.clusterm_uni.do,
            for y = 1:plm.nY,
                if opts.designperinput,
                    loopM = y;
                    distmax = zeros(plm.nP{1}(1),plm.nC(1));
                else
                    loopM = 1:plm.nM;
                    distmax = zeros(plm.nP{1}(1),sum(plm.nC));
                end
                j = 1;
                for m = loopM,
                    for c = 1:plm.nC(m),
                        distmax(:,j) = plm.Gclmmax{y}{m}{c};
                        j = j + 1;
                    end
                end
                distmax = max(distmax,[],2);
                for m = loopM,
                    for c = 1:plm.nC(m),
                        palm_quicksave( ...
                            palm_datapval(plm.Gclm{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,'_clusterm',plm.Gname{m}{c},'_cfwep',ystr{y},mstr{m},cstr{c}));
                    end
                end
            end
        end
        
        % TFCE
        if opts.tfce_uni.do,
            for y = 1:plm.nY,
                if opts.designperinput,
                    loopM = y;
                    distmax = zeros(plm.nP{1}(1),plm.nC(1));
                else
                    loopM = 1:plm.nM;
                    distmax = zeros(plm.nP{1}(1),sum(plm.nC));
                end
                j = 1;
                for m = loopM,
                    for c = 1:plm.nC(m),
                        distmax(:,j) = plm.Gtfcemax{y}{m}{c};
                        j = j + 1;
                    end
                end
                distmax = max(distmax,[],2);
                for m = loopM,
                    for c = 1:plm.nC(m),
                        palm_quicksave( ...
                            palm_datapval(plm.Gtfce{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,'_tfce',plm.Gname{m}{c},'_cfwep',ystr{y},mstr{m},cstr{c}));
                    end
                end
            end
            if opts.FDR,
                for y = 1:plm.nY,
                    if opts.designperinput,
                        loopM = y;
                        pmerged = zeros(plm.nC(1),plm.Ysiz(y));
                    else
                        loopM = 1:plm.nM;
                        pmerged = zeros(sum(plm.nC),plm.Ysiz(y));
                    end
                    j = 1;
                    for m = loopM,
                        for c = 1:plm.nC(m),
                            pmerged(j,:) = plm.Gtfcepperm{y}{m}{c};
                            j = j + 1;
                        end
                    end
                    pfdradj = reshape(fastfdr(pmerged(:)),size(pmerged));
                    j = 1;
                    for m = loopM,
                        for c = 1:plm.nC(m),
                            palm_quicksave(pfdradj(j,:),1,opts,plm,y,m,c, ...
                                sprintf('%s',opts.o,'_tfce',plm.Gname{m}{c},'_cfdrp',ystr{y},mstr{m},cstr{c}));
                            j = j + 1;
                        end
                    end
                end
            end
        end
    end
    
    % Save FWER & FDR corrected across modalities and contrasts.
    if opts.corrmod && opts.corrcon,
        fprintf('Saving p-values (corrected across modalities and contrasts).\n')
        
        % FWER correction (non-spatial stats)
        if opts.designperinput,
            distmax = zeros(plm.nP{1}(1),plm.nY*plm.nC(1));
        else
            distmax = zeros(plm.nP{1}(1),plm.nY*sum(plm.nC));
        end
        j = 1;
        for y = 1:plm.nY,
            if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
            for m = loopM,
                for c = 1:plm.nC(m),
                    distmax(:,j) = plm.Gmax{y}{m}{c};
                    j = j + 1;
                end
            end
        end
        distmax = max(distmax,[],2);
        for y = 1:plm.nY,
            if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
            for m = loopM,
                for c = 1:plm.nC(m),
                    palm_quicksave( ...
                        palm_datapval(plm.G{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                        sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},'_mcfwep',ystr{y},mstr{m},cstr{c}));
                end
            end
        end
        
        % FDR correction (non-spatial stats)
        if opts.FDR,
            if opts.designperinput,
                pmerged = zeros(plm.nC(1),sum(plm.Ysiz));
            else
                pmerged = zeros(sum(plm.nC),sum(plm.Ysiz));
            end
            j = 1;
            for y = 1:plm.nY,
                if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
                for m = loopM,
                    for c = 1:plm.nC(m),
                        pmerged(c,plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)) = plm.Gpperm{y}{m}{c};
                        j = j + 1;
                    end
                end
            end
            pfdradj = reshape(fastfdr(pmerged(:)),size(pmerged));
            for y = 1:plm.nY,
                if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
                for m = loopM,
                    for c = 1:plm.nC(m),
                        palm_quicksave(pfdradj(c,plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,plm.Ykindstr{y},plm.Gname{m}{c},'_mcfdrp',ystr{y},mstr{m},cstr{c}));
                    end
                end
            end
        end
        
        % Cluster extent
        if opts.clustere_uni.do,
            if opts.designperinput,
                distmax = zeros(plm.nP{1}(1),plm.nY*plm.nC(1));
            else
                distmax = zeros(plm.nP{1}(1),plm.nY*sum(plm.nC));
            end
            j = 1;
            for y = 1:plm.nY,
                if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
                for m = loopM,
                    for c = 1:plm.nC(m),
                        distmax(:,j) = plm.Gclemax{y}{m}{c};
                        j = j + 1;
                    end
                end
            end
            distmax = max(distmax,[],2);
            for y = 1:plm.nY,
                if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
                for m = loopM,
                    for c = 1:plm.nC(m),
                        palm_quicksave( ...
                            palm_datapval(plm.Gcle{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,'_clustere',plm.Gname{m}{c},'_mcfwep',ystr{y},mstr{m},cstr{c}));
                    end
                end
            end
        end
        
        % Cluster mass
        if opts.clusterm_uni.do,
            if opts.designperinput,
                distmax = zeros(plm.nP{1}(1),plm.nY*plm.nC(1));
            else
                distmax = zeros(plm.nP{1}(1),plm.nY*sum(plm.nC));
            end
            j = 1;
            for y = 1:plm.nY,
                if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
                for m = loopM,
                    for c = 1:plm.nC(m),
                        distmax(:,j) = plm.Gclmmax{y}{m}{c};
                        j = j + 1;
                    end
                end
            end
            distmax = max(distmax,[],2);
            for y = 1:plm.nY,
                if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
                for m = loopM,
                    for c = 1:plm.nC(m),
                        palm_quicksave( ...
                            palm_datapval(plm.Gclm{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,'_clusterm',plm.Gname{m}{c},'_mcfwep',ystr{y},mstr{m},cstr{c}));
                    end
                end
            end
        end
        
        % TFCE
        if opts.tfce_uni.do,
            if opts.designperinput,
                distmax = zeros(plm.nP{1}(1),plm.nY*plm.nC(1));
            else
                distmax = zeros(plm.nP{1}(1),plm.nY*sum(plm.nC));
            end
            j = 1;
            for y = 1:plm.nY,
                if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
                for m = loopM,
                    for c = 1:plm.nC(m),
                        distmax(:,j) = plm.Gtfcemax{y}{m}{c};
                        j = j + 1;
                    end
                end
            end
            distmax = max(distmax,[],2);
            for y = 1:plm.nY,
                if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
                for m = loopM,
                    for c = 1:plm.nC(m),
                        palm_quicksave( ...
                            palm_datapval(plm.Gtfce{y}{m}{c},distmax,false),1,opts,plm,y,m,c, ...
                            sprintf('%s',opts.o,'_tfce',plm.Gname{m}{c},'_mcfwep',ystr{y},mstr{m},cstr{c}));
                    end
                end
            end
            if opts.FDR,
                if opts.designperinput,
                    pmerged = zeros(plm.nC(1),sum(plm.Ysiz));
                else
                    pmerged = zeros(sum(plm.nC),sum(plm.Ysiz));
                end
                j = 1;
                for y = 1:plm.nY,
                    if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
                    for m = loopM,
                        for c = 1:plm.nC(m),
                            pmerged(c,plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)) = plm.Gtfcepperm{y}{m}{c};
                            j = j + 1;
                        end
                    end
                end
                pfdradj = reshape(fastfdr(pmerged(:)),size(pmerged));
                for y = 1:plm.nY,
                    if opts.designperinput, loopM = y; else loopM = 1:plm.nM; end
                    for m = loopM,
                        for c = 1:plm.nC(m),
                            palm_quicksave(pfdradj(c,plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)),1,opts,plm,y,m,c, ...
                                sprintf('%s',opts.o,'_tfce',plm.Gname{m}{c},'_mcfdrp',ystr{y},mstr{m},cstr{c}));
                        end
                    end
                end
            end
        end
    end
end

% Save NPC between modalities, corrected within contrasts
if opts.npcmod && ~ opts.npccon,
    fprintf('Saving p-values for NPC between modalities (uncorrected and corrected within contrasts).\n');
    for m = 1:plm.nM,
        for c = 1:plm.nC(m),
            
            % For the Nichols method, the maxima for all modalities are pooled
            if isnichols,
                plm.Tmax{m}{c} = plm.Tmax{m}{c}(:);
            end
            
            % NPC p-value
            palm_quicksave(plm.Tpperm{m}{c},1,opts,plm,[],m,c, ...
                sprintf('%s',opts.o,plm.Ykindstr{1},plm.npcstr,plm.Tname,'_uncp',mstr{m},cstr{c}));
            
            % NPC FWER-corrected
            palm_quicksave( ...
                palm_datapval(plm.T{m}{c},plm.Tmax{m}{c},npcrev),1,opts,plm,[],m,c, ...
                sprintf('%s',opts.o,plm.Ykindstr{1},plm.npcstr,plm.Tname,'_fwep',mstr{m},cstr{c}));
            
            % NPC FDR
            if opts.FDR,
                palm_quicksave(fastfdr(plm.Tpperm{m}{c}),1,opts,plm,[],m,c, ...
                    sprintf('%s',opts.o,plm.Ykindstr{1},plm.npcstr,plm.Tname,'_fdrp',mstr{m},cstr{c}));
            end
            
            % Parametric combined pvalue
            if opts.savepara && ~ plm.nonpcppara,
                palm_quicksave(plm.Tppara{m}{c},1,opts,plm,[],m,c, ...
                    sprintf('%s',opts.o,plm.Ykindstr{1},plm.npcstr,plm.Tname,'_uncparap',mstr{m},cstr{c}));
            end
            
            % Cluster extent NPC results.
            if opts.clustere_npc.do,
                
                % Cluster extent statistic.
                palm_quicksave(plm.Tcle{m}{c},0,opts,plm,[],m,c, ...
                    sprintf('%s',opts.o,'_clustere',plm.npcstr,plm.Tname,mstr{m},cstr{c}));
                
                % Cluster extent FWER p-value
                palm_quicksave( ...
                    palm_datapval(plm.Tcle{m}{c},plm.Tclemax{m}{c},false),1,opts,plm,y,m,c,...
                    sprintf('%s',opts.o,'_clustere',plm.npcstr,plm.Tname,'_fwep',mstr{m},cstr{c}));
            end
            
            % Cluster mass NPC results.
            if opts.clusterm_npc.do,
                
                % Cluster mass statistic.
                palm_quicksave(plm.Tclm{m}{c},0,opts,plm,[],m,c, ...
                    sprintf('%s',opts.o,'_clusterm',plm.npcstr,plm.Tname,mstr{m},cstr{c}));
                
                % Cluster mass FWER p-value
                palm_quicksave( ...
                    palm_datapval(plm.Tclm{m}{c},plm.Tclmmax{m}{c},false),1,opts,plm,y,m,c,...
                    sprintf('%s',opts.o,'_clusterm',plm.npcstr,plm.Tname,'_fwep',mstr{m},cstr{c}));
            end
            
            % TFCE NPC results.
            if opts.tfce_npc.do,
                
                % TFCE statistic.
                palm_quicksave(plm.Ttfce{m}{c},0,opts,plm,[],m,c, ...
                    sprintf('%s',opts.o,'_tfce',plm.npcstr,plm.Tname,mstr{m},cstr{c}));
                
                % TFCE p-value
                palm_quicksave(plm.Ttfcepperm{m}{c},1,opts,plm,[],m,c,...
                    sprintf('%s',opts.o,'_tfce',plm.npcstr,plm.Tname,'_uncp',mstr{m},cstr{c}));
                
                % TFCE FWER p-value
                palm_quicksave( ...
                    palm_datapval(plm.Ttfce{m}{c},plm.Ttfcemax{m}{c},false),1,opts,plm,[],m,c,...
                    sprintf('%s',opts.o,'_tfce',plm.npcstr,plm.Tname,'_fwep',mstr{m},cstr{c}));
                
                % TFCE FDR p-value
                if opts.FDR,
                    palm_quicksave(fastfdr(plm.Ttfcepperm{m}{c}),1,opts,plm,[],m,c,...
                        sprintf('%s',opts.o,'_tfce',plm.npcstr,plm.Tname,'_uncp',mstr{m},cstr{c}));
                end
            end
        end
    end
end

% Save NPC between modalities, corrected across contrasts
if opts.npcmod && ~ opts.npccon && opts.corrcon,
    fprintf('Saving p-values for NPC between modalities (corrected across contrasts).\n');
    
    % FWER correction (non-spatial stats)
    distmax = zeros(plm.nP{1}(1),sum(plm.nC));
    j = 1;
    for m = 1:plm.nM,
        for c = 1:plm.nC(m),
            distmax(:,j) = plm.Tmax{m}{c};
            j = j + 1;
        end
    end
    distmax = max(distmax,[],2);
    for m = 1:plm.nM,
        for c = 1:plm.nC(m),
            palm_quicksave( ...
                palm_datapval(plm.T{m}{c},distmax,npcrev),1,opts,plm,[],m,c,...
                sprintf('%s',opts.o,plm.Ykindstr{1},plm.npcstr,plm.Tname,'_cfwep',mstr{m},cstr{c}));
        end
    end
    
    % FDR correction (non-spatial stats)
    if opts.FDR,
        pmerged = zeros(sum(plm.nC),plm.Ysiz(1));
        j = 1;
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                pmerged(:,j) = plm.Tpperm{m}{c};
                j = j + 1;
            end
        end
        pfdradj = reshape(fastfdr(pmerged(:)),sum(plm.nC),plm.Ysiz(1));
        j = 1;
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                palm_quicksave(pfdradj(:,j),1,opts,plm,[],m,c, ...
                    sprintf('%s',opts.o,plm.Ykindstr{1},plm.npcstr,plm.Tname,'_cfdrp',mstr{m},cstr{c}));
                j = j + 1;
            end
        end
    end
    
    % Cluster extent NPC
    if opts.clustere_npc.do,
        distmax = zeros(plm.nP{1}(1),sum(plm.nC));
        j = 1;
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                distmax(:,j) = plm.Tclemax{m}{c};
                j = j + 1;
            end
        end
        distmax = max(distmax,[],2);
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                palm_quicksave( ...
                    palm_datapval(plm.Tcle{m}{c},distmax,false),1,opts,plm,[],m,c,...
                    sprintf('%s',opts.o,'_clustere',plm.npcstr,plm.Tname,'_cfwep',mstr{m},cstr{c}));
            end
        end
    end
    
    % Cluster mass NPC
    if opts.clustere_npc.do,
        distmax = zeros(plm.nP{1}(1),sum(plm.nC));
        j = 1;
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                distmax(:,j) = plm.Tclmmax{m}{c};
                j = j + 1;
            end
        end
        distmax = max(distmax,[],2);
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                palm_quicksave( ...
                    palm_datapval(plm.Tclm{m}{c},distmax,false),1,opts,plm,[],m,c,...
                    sprintf('%s',opts.o,'_clusterm',plm.npcstr,plm.Tname,'_cfwep',mstr{m},cstr{c}));
            end
        end
    end
    
    % TFCE NPC
    if opts.tfce_npc.do,
        distmax = zeros(plm.nP{1}(1),sum(plm.nC));
        j = 1;
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                distmax(:,j) = plm.Ttfcemax{m}{c};
                j = j + 1;
            end
        end
        distmax = max(distmax,[],2);
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                palm_quicksave( ...
                    palm_datapval(plm.Ttfce{m}{c},distmax,false),1,opts,plm,[],m,c,...
                    sprintf('%s',opts.o,'_tfce',plm.npcstr,plm.Tname,'_cfwep',mstr{m},cstr{c}));
            end
        end
        if opts.FDR,
            pmerged = zeros(sum(plm.nC),plm.Ysiz(1));
            j = 1;
            for m = 1:plm.nM,
                for c = 1:plm.nC(m),
                    pmerged(:,j) = plm.Ttfcepperm{m}{c};
                    j = j + 1;
                end
            end
            pfdradj = reshape(fastfdr(pmerged(:)),sum(plm.nC),plm.Ysiz(1));
            j = 1;
            for m = 1:plm.nM,
                for c = 1:plm.nC(m),
                    palm_quicksave(pfdradj(:,j),1,opts,plm,[],m,c, ...
                        sprintf('%s',opts.o,'_tfce',plm.npcstr,plm.Tname,'_cfdrp',mstr{m},cstr{c}));
                    j = j + 1;
                end
            end
        end
    end
end

% Save NPC between contrasts, corrected within modality
if opts.npccon,
    fprintf('Saving p-values for NPC between contrasts (uncorrected and corrected within modality).\n');
    
    for j = 1:numel(plm.Tmax),
        
        % For the Nichols method, the maxima for all modalities are pooled
        if isnichols,
            plm.Tmax{j} = plm.Tmax{j}(:);
        end
        
        % NPC p-value
        palm_quicksave(plm.Tpperm{j},1,opts,plm,j,[],[], ...
            sprintf('%s',opts.o,plm.Ykindstr{1},plm.npcstr,plm.Tname,'_uncp',jstr{j}));
        
        % NPC FWER-corrected
        palm_quicksave( ...
            palm_datapval(plm.T{j},plm.Tmax{j},npcrev),1,opts,plm,j,[],[], ...
            sprintf('%s',opts.o,plm.Ykindstr{1},plm.npcstr,plm.Tname,'_fwep',jstr{j}));
        
        % NPC FDR
        if opts.FDR,
            palm_quicksave(fastfdr(plm.Tpperm{j}),1,opts,plm,j,[],[], ...
                sprintf('%s',opts.o,plm.Ykindstr{1},plm.npcstr,plm.Tname,'_fdrp',jstr{j}));
        end
        
        % Parametric combined pvalue
        if opts.savepara && ~ plm.nonpcppara,
            palm_quicksave(plm.Tppara{j},1,opts,plm,j,[],[], ...
                sprintf('%s',opts.o,plm.Ykindstr{1},plm.npcstr,plm.Tname,'_uncparap',jstr{j}));
        end
        
        % Cluster extent NPC results.
        if opts.clustere_npc.do,
            
            % Cluster extent statistic.
            palm_quicksave(plm.Tcle{j},0,opts,plm,j,[],[], ...
                sprintf('%s',opts.o,'_clustere',plm.npcstr,plm.Tname,jstr{j}));
            
            % Cluster extent FWER p-value
            palm_quicksave( ...
                palm_datapval(plm.Tcle{j},plm.Tclemax{j},false),1,opts,plm,j,[],[],...
                sprintf('%s',opts.o,'_clustere',plm.npcstr,plm.Tname,'_fwep',jstr{j}));
        end
        
        % Cluster mass NPC results.
        if opts.clusterm_npc.do,
            
            % Cluster mass statistic.
            palm_quicksave(plm.Tclm{j},0,opts,plm,j,[],[], ...
                sprintf('%s',opts.o,'_clusterm',plm.npcstr,plm.Tname,jstr{j}));
            
            % Cluster mass FWER p-value
            palm_quicksave( ...
                palm_datapval(plm.Tclm{j},plm.Tclmmax{j},false),1,opts,plm,j,[],[],...
                sprintf('%s',opts.o,'_clusterm',plm.npcstr,plm.Tname,'_fwep',jstr{j}));
        end
        
        % TFCE NPC results.
        if opts.tfce_npc.do,
            
            % TFCE statistic.
            palm_quicksave(plm.Ttfce{j},0,opts,plm,j,[],[], ...
                sprintf('%s',opts.o,'_tfce',plm.npcstr,plm.Tname,jstr{j}));
            
            % TFCE p-value
            palm_quicksave(plm.Ttfcepperm{j},1,opts,plm,j,[],[],...
                sprintf('%s',opts.o,'_tfce',plm.npcstr,plm.Tname,'_uncp',jstr{j}));
            
            % TFCE FWER p-value
            palm_quicksave( ...
                palm_datapval(plm.Ttfce{j},plm.Ttfcemax{j},false),1,opts,plm,j,[],[],...
                sprintf('%s',opts.o,'_tfce',plm.npcstr,plm.Tname,'_fwep',jstr{j}));
            
            % TFCE FDR p-value
            if opts.FDR,
                palm_quicksave(fastfdr(plm.Ttfcepperm{j}),1,opts,plm,j,[],[], ...
                    sprintf('%s',opts.o,'_tfce',plm.npcstr,plm.Tname,'_fdrp',jstr{j}));
            end
        end
    end
end

% Save the NPC over contrasts, corrected for modalities
if ~ opts.npcmod && opts.npccon && opts.corrmod,
    fprintf('Saving p-values for NPC over contrasts (corrected across modalities).\n')
    
    % NPC FWER-corrected across modalities.
    distmax = npcextr(cat(2,plm.Tmax{:}),2);
    for y = 1:numel(plm.nY),
        palm_quicksave( ...
            palm_datapval(plm.T{y},distmax,npcrev),1,opts,plm,[],[],[], ...
            sprintf('%s',opts.o,plm.Ykindstr{y},plm.npcstr,plm.Tname,'_mfwep',ystr{y}));
        
        % Parametric combined pvalue
        if opts.savepara && ~ plm.nonpcppara,
            palm_quicksave(plm.Tppara{y},1,opts,plm,[],[],[], ...
                sprintf('%s',opts.o,plm.Ykindstr{y},plm.npcstr,plm.Tname,'_uncparap',ystr{y}));
        end
    end
    
    % NPC FDR correction (non-spatial stats)
    if opts.FDR,
        pmerged = zeros(sum(plm.Ysiz),1);
        for y = 1:plm.nY,
            pmerged(plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)) = plm.Tpperm{y};
        end
        pfdradj = fastfdr(pmerged);
        for y = 1:plm.nY,
            palm_quicksave(pfdradj(plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)),1,opts,plm,[],[],[], ...
                sprintf('%s',opts.o,plm.Ykindstr{y},plm.Tname,'_mfdrp',ystr{y}));
        end
    end
    
    % NPC FDR-corrected across modalities.
    distmax = npcextr(cat(2,plm.Tmax{:}),2);
    for y = 1:numel(plm.nY),
        palm_quicksave( ...
            palm_datapval(plm.T{y},distmax,npcrev),1,opts,plm,[],[],[], ...
            sprintf('%s',opts.o,plm.Ykindstr{y},plm.npcstr,plm.Tname,'_mfwep',ystr{y}));
        
        % Parametric combined pvalue
        if opts.savepara && ~ plm.nonpcppara,
            palm_quicksave(plm.Tppara{y},1,opts,plm,[],[],[], ...
                sprintf('%s',opts.o,plm.Ykindstr{y},plm.npcstr,plm.Tname,'_uncparap',ystr{y}));
        end
    end
    
    % Cluster extent NPC results.
    if opts.clustere_npc.do,
        distmax = npcextr(cat(2,plm.Tclemax{:}),2);
        for y = 1:numel(plm.nY),
            
            % Cluster extent statistic.
            palm_quicksave(plm.Tcle{y},0,opts,plm,y,[],[], ...
                sprintf('%s',opts.o,'_clustere',plm.npcstr,plm.Tname,ystr{y}));
            
            % Cluster extent FWER p-value
            palm_quicksave( ...
                palm_datapval(plm.Tcle{y},distmax,false),1,opts,plm,y,[],[],...
                sprintf('%s',opts.o,'_clustere',plm.npcstr,plm.Tname,'_mfwep',ystr{y}));
        end
    end
    
    % Cluster mass NPC results.
    if opts.clusterm_npc.do,
        distmax = npcextr(cat(2,plm.Tclmmax{:}),2);
        for y = 1:numel(plm.nY),
            
            % Cluster extent statistic.
            palm_quicksave(plm.Tclm{y},0,opts,plm,y,[],[], ...
                sprintf('%s',opts.o,'_clusterm',plm.npcstr,plm.Tname,ystr{y}));
            
            % Cluster extent FWER p-value
            palm_quicksave( ...
                palm_datapval(plm.Tclm{y},distmax,false),1,opts,plm,y,[],[],...
                sprintf('%s',opts.o,'_clusterm',plm.npcstr,plm.Tname,'_mfwep',ystr{y}));
        end
    end
    
    % TFCE NPC results.
    if opts.tfce_npc.do,
        distmax = npcextr(cat(2,plm.Ttfce{:}),2);
        for y = 1:numel(plm.nY),
            
            % Cluster extent statistic.
            palm_quicksave(plm.Ttfce{y},0,opts,plm,y,[],[], ...
                sprintf('%s',opts.o,'_tfce',plm.npcstr,plm.Tname,ystr{y}));
            
            % Cluster extent FWER p-value
            palm_quicksave( ...
                palm_datapval(plm.Ttfce{y},distmax,false),1,opts,plm,y,[],[],...
                sprintf('%s',opts.o,'_tfce',plm.npcstr,plm.Tname,'_mfwep',ystr{y}));
        end
        
        % NPC FDR correction TFCE
        if opts.FDR,
            pmerged = zeros(sum(plm.Ysiz),1);
            for y = 1:plm.nY,
                pmerged(plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)) = plm.Ttfcepperm{y};
            end
            pfdradj = fastfdr(pmerged);
            for y = 1:plm.nY,
                palm_quicksave(pfdradj(plm.Ycumsiz(y)+1:plm.Ycumsiz(y+1)),1,opts,plm,[],[],[], ...
                    sprintf('%s',opts.o,'_tfce',plm.Tname,'_mfdrp',ystr{y}));
            end
        end
    end
end

% Save the MV results for each contrast
if opts.MV || opts.CCA,
    fprintf('Saving p-values for classical multivariate (uncorrected and corrected within contrast).\n')
    for m = 1:plm.nM,
        for c = 1:plm.nC(m),
            % MV p-value
            palm_quicksave(plm.Qpperm{m}{c},1,opts,plm,[],[],[], ...
                sprintf('%s',opts.o,plm.Ykindstr{1},plm.mvstr,plm.Qname{m}{c},'_uncp',mstr{m},cstr{c}));
            
            % MV FWER-corrected within modality and contrast.
            palm_quicksave( ...
                palm_datapval(plm.Q{m}{c},plm.Qmax{m}{c},false),1,opts,plm,[],[],[], ...
                sprintf('%s',opts.o,plm.Ykindstr{1},plm.mvstr,plm.Qname{m}{c},'_fwep',mstr{m},cstr{c}));
            
            % MV FDR
            if opts.FDR,
                palm_quicksave(fastfdr(plm.Qpperm{m}{c}),1,opts,plm,[],[],[], ...
                    sprintf('%s',opts.o,plm.Ykindstr{1},plm.mvstr,plm.Qname{m}{c},'_fdrp',mstr{m},cstr{c}));
            end
            
            % Parametric MV pvalue
            if opts.savepara && ~ plm.nomvppara,
                palm_quicksave(plm.Qppara{m}{c},1,opts,plm,[],[],[], ...
                    sprintf('%s',opts.o,plm.Ykindstr{1},plm.mvstr,plm.Qname{m}{c},'_uncparap',mstr{m},cstr{c}));
            end
            
            % Cluster extent MV results.
            if opts.clustere_mv.do,
                
                % Cluster extent statistic.
                palm_quicksave(plm.Qcle{m}{c},0,opts,plm,[],[],[], ...
                    sprintf('%s',opts.o,'_clustere',plm.mvstr,plm.Qname{m}{c},mstr{m},cstr{c}));
                
                % Cluster extent FWER p-value
                palm_quicksave( ...
                    palm_datapval(plm.Qcle{m}{c},plm.Qclemax{m}{c},false),1,opts,plm,[],[],[],...
                    sprintf('%s',opts.o,'_clustere',plm.mvstr,plm.Qname{m}{c},'_fwep',mstr{m},cstr{c}));
            end
            
            % Cluster mass MV results.
            if opts.clusterm_mv.do,
                
                % Cluster mass statistic.
                palm_quicksave(plm.Qclm{m}{c},0,opts,plm,[],[],[], ...
                    sprintf('%s',opts.o,'_clusterm',plm.mvstr,plm.Qname{m}{c},mstr{m},cstr{c}));
                
                % Cluster mass FWER p-value
                palm_quicksave( ...
                    palm_datapval(plm.Qclm{m}{c},plm.Qclmmax{m}{c},false),1,opts,plm,[],[],[],...
                    sprintf('%s',opts.o,'_clusterm',plm.mvstr,plm.Qname{m}{c},'_fwep',mstr{m},cstr{c}));
            end
            
            % TFCE MV results.
            if opts.tfce_mv.do,
                
                % TFCE statistic.
                palm_quicksave(plm.Qtfce{m}{c},0,opts,plm,[],[],[], ...
                    sprintf('%s',opts.o,'_tfce',plm.mvstr,plm.Qname{m}{c},mstr{m},cstr{c}));
                
                % TFCE p-value
                palm_quicksave(plm.Qtfcepperm{m}{c},1,opts,plm,[],[],[],...
                    sprintf('%s',opts.o,'_tfce',plm.mvstr,plm.Qname,'_uncp',mstr{m},cstr{c}));
                
                % TFCE FWER p-value
                palm_quicksave(palm_datapval( ...
                    plm.Qtfce{m}{c},plm.Qtfcemax{m}{c},false),1,opts,plm,[],[],[], ...
                    sprintf('%s',opts.o,'_tfce',plm.mvstr,plm.Qname{m}{c},'_fwep',mstr{m},cstr{c}));
                
                % TFCE MV FDR
                if opts.FDR,
                    palm_quicksave(fastfdr(plm.Qtfcepperm{m}{c}),1,opts,plm,[],[],[], ...
                        sprintf('%s',opts.o,'_tfce',plm.mvstr,plm.Qname{m}{c},'_fdrp',mstr{m},cstr{c}));
                end
            end
        end
    end
end

% Save FWER corrected across contrasts for MV.
if ( opts.MV  || opts.CCA ) && opts.corrcon,
    fprintf('Saving p-values for MANOVA/MANCOVA (corrected across contrasts).\n')
    
    % FWER correction (non-spatial stats)
    distmax = zeros(plm.nP{1}(1),sum(plm.nC));
    j = 1;
    for m = 1:plm.nM,
        for c = 1:plm.nC(m),
            distmax(:,j) = plm.Qmax{m}{c};
            j = j + 1;
        end
    end
    distmax = max(distmax,[],2);
    for m = 1:plm.nM,
        for c = 1:plm.nC(m),
            palm_quicksave( ...
                palm_datapval(plm.T{m}{c},distmax,false),1,opts,plm,[],m,c,...
                sprintf('%s',opts.o,plm.Ykindstr{1},plm.mvstr,plm.Qname{m}{c},'_cfwep',mstr{m},cstr{c}));
        end
    end
    
    % FDR correction (non-spatial stats)
    if opts.FDR,
        pmerged = zeros(sum(plm.nC),plm.Ysiz(1));
        j = 1;
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                pmerged(:,j) = plm.Qpperm{m}{c};
                j = j + 1;
            end
        end
        pfdradj = reshape(fastfdr(pmerged(:)),sum(plm.nC),plm.Ysiz(1));
        j = 1;
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                palm_quicksave(pfdradj(:,j),1,opts,plm,[],m,c, ...
                    sprintf('%s',opts.o,plm.Ykindstr{1},plm.mvstr,plm.Tname,'_cfdrp',mstr{m},cstr{c}));
                j = j + 1;
            end
        end
    end
    
    % Cluster extent MV
    if opts.clustere_mv.do,
        distmax = zeros(plm.nP{1}(1),sum(plm.nC));
        j = 1;
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                distmax(:,j) = plm.Qclemax{m}{c};
                j = j + 1;
            end
        end
        distmax = max(distmax,[],2);
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                palm_quicksave( ...
                    palm_datapval(plm.Qcle{m}{c},distmax,false),1,opts,plm,[],m,c,...
                    sprintf('%s',opts.o,'_clustere',plm.mvstr,plm.Qname{m}{c},'_cfwep',mstr{m},cstr{c}));
            end
        end
    end
    
    % Cluster mass MV
    if opts.clusterm_mv.do,
        distmax = zeros(plm.nP{1}(1),sum(plm.nC));
        j = 1;
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                distmax(:,j) = plm.Qclmmax{m}{c};
                j = j + 1;
            end
        end
        distmax = max(distmax,[],2);
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                palm_quicksave( ...
                    palm_datapval(plm.Qclm{m}{c},distmax,false),1,opts,plm,[],m,c,...
                    sprintf('%s',opts.o,'_clusterm',plm.mvstr,plm.Qname{m}{c},'_cfwep',mstr{m},cstr{c}));
            end
        end
    end
    
    % TFCE MV
    if opts.tfce_mv.do,
        
        % FWER correction
        distmax = zeros(plm.nP{1}(1),sum(plm.nC));
        j = 1;
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                distmax(:,j) = plm.Qtfcemax{m}{c};
                j = j + 1;
            end
        end
        distmax = max(distmax,[],2);
        for m = 1:plm.nM,
            for c = 1:plm.nC(m),
                palm_quicksave( ...
                    palm_datapval(plm.Qtfce{m}{c},distmax,false),1,opts,plm,[],m,c,...
                    sprintf('%s',opts.o,'_tfce',plm.mvstr,plm.Qname{m}{c},'_cfwep',mstr{m},cstr{c}));
            end
        end
        
        % FDR correction TFCE
        if opts.FDR,
            pmerged = zeros(sum(plm.nC),plm.Ysiz(1));
            j = 1;
            for m = 1:plm.nM,
                for c = 1:plm.nC(m),
                    pmerged(:,j) = plm.Qtfcepperm{m}{c};
                    j = j + 1;
                end
            end
            pfdradj = reshape(fastfdr(pmerged(:)),sum(plm.nC),plm.Ysiz(1));
            j = 1;
            for m = 1:plm.nM,
                for c = 1:plm.nC(m),
                    palm_quicksave(pfdradj(:,j),1,opts,plm,[],m,c, ...
                        sprintf('%s',opts.o,'_tfce',plm.mvstr,plm.Qname{m}{c},'_cfdrp',mstr{m},cstr{c}));
                    j = j + 1;
                end
            end
        end
    end
end

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%  F U N C T I O N S  %%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% ==============================================================
% Below are the functions for each of the regression methods:
% ==============================================================
function [Mr,Y] = evperdat(P,Y,m,c,plm)
% This is the same as Draper-Stoneman, for when
% there one EV per datum. Y remains unchanged.
Mr = P*plm.Mp{m}{c};

% ==============================================================
function [Mr,Y] = noz(P,Y,m,c,plm)
% This is equivalent to Draper-Stoneman, as when there is no Z
% Y remains unchanged.
Mr = P*plm.X{m}{c};

% ==============================================================
function [Mr,Yr] = exact(P,Y,m,c,plm)
% The "exact" method, in which the coefficients for
% the nuisance are known.
Yr = Y - plm.Z{m}{c}*plm.g;
Mr = P*plm.X{m}{c};

% ==============================================================
function [Mr,Y] = draperstoneman(P,Y,m,c,plm)
% Draper and Stoneman (1966) method.
% Y remains unchanged
Mr = horzcat(P*plm.X{m}{c},plm.Z{m}{c});

% ==============================================================
function [Mr,Yr] = stillwhite(P,Y,m,c,plm)
% A method following the same logic as the one
% proposed by Still and White (1981)
Yr = plm.Rz{m}{c}*Y;
Mr = P*plm.X{m}{c};

% ==============================================================
function [Mr,Yr] = freedmanlane(P,Y,m,c,plm)
% The Freedman and Lane (1983) method.
Mr = plm.Mp{m}{c};
Yr = (P'*plm.Rz{m}{c} + plm.Hz{m}{c})*Y;

% ==============================================================
function [Mr,Yr] = manly(P,Y,m,c,plm)
% The Manly (1986) method.
Mr = plm.Mp{m}{c};
Yr = P'*Y;

% ==============================================================
function [Mr,Yr] = terbraak(P,Y,m,c,plm)
% The ter Braak (1992) method.
Mr = plm.Mp{m}{c};
Yr = (P'*plm.Rm{m}{c} + plm.Hm{m}{c})*Y; % original method
% Yr = P'*plm.Rm{m}{c}*Y; % alternative (causes unpermuted stat to be 0)

% ==============================================================
function [Mr,Yr] = kennedy(P,Y,m,c,plm)
% The Kennedy (1996) method. This method should NEVER be used.
Mr = plm.Rz{m}{c}*plm.X{m}{c};
Yr = P'*plm.Rz{m}{c}*Y;

% ==============================================================
function [Mr,Yr] = huhjhun(P,Y,m,c,plm)
% The Huh and Jhun (2001) method, that fixes the issues
% with Kennedy's, but doesn't allow block permutation.
Mr = plm.hj{m}{c}'*plm.Rz{m}{c}*plm.X{m}{c};
Yr = P'*plm.hj{m}{c}'*plm.Rz{m}{c}*Y;

% ==============================================================
function [Mr,Y] = smith(P,Y,m,c,plm)
% The Smith method, i.e., orthogonalization.
% Y remains unchanged
Mr = horzcat(P*plm.Rz{m}{c}*plm.X{m}{c},plm.Z{m}{c});

% ==============================================================
% Below are the functions to compute univariate statistics:
% ==============================================================
function G = fastr(M,psi,Y,m,c,plm)
% This only works if:
% - M and Y have zero mean.
% - rank(contrast) = 1
%
% Inputs:
% M   : design matrix (demeaned)
% psi : regression coefficients
% Y   : data (demeaned)
% plm : a struct with many things as generated by
%       'palm_backend.m' and 'palm_takeargs.m'
%
% Outputs:
% G   : Pearson's correlation coefficient (r).

G = fastrsq(M,psi,Y,plm);
G = sign(plm.eC{m}{c}'*psi).*G.^.5;

% ==============================================================
function G = fastrsq(M,psi,Y,m,c,plm)
% This only works if:
% - M and Y have zero mean.
%
% Inputs:
% M   : design matrix (demeaned)
% psi : regression coefficients
% Y   : data (demeaned)
% plm : a struct with many things as generated by
%       'palm_backend.m' and 'palm_takeargs.m'
%
% Outputs:
% G   : R^2, i.e., the coefficient of determination.

tmp = plm.eC{m}{c}/(plm.eC{m}{c}'/(M'*M)*plm.eC{m}{c})*plm.eC{m}{c}';
G   = sum((tmp'*psi).*psi,1);
den = sum(Y.^2,1);
G   = G./den;

% ==============================================================
function [G,df2] = fastt(M,psi,res,m,c,plm)
% This works only if:
% - rank(contrast) = 1
% - number of variance groups = 1
%
% Inputs:
% M   : design matrix
% psi : regression coefficients
% res : residuals
% plm : a struct with many things as generated by
%       'palm_backend.m' and 'palm_takeargs.m'
%
% Outputs:
% G   : t statistic.
% df2 : Degrees of freedom. df1 is 1 for the t statistic.

df2 = plm.N-plm.rM{m}(c);
if plm.evperdat{m}{c},
    G   = psi;
    den = sqrt(sum(res.^2,1)./sum(M.*M,1)./df2);
else
    G   = plm.eC{m}{c}'*psi;
    den = sqrt(plm.eC{m}{c}'/(M'*M)*plm.eC{m}{c}*sum(res.^2)./df2);
end
G   = G./den;

% ==============================================================
function [G,df2] = fastf(M,psi,res,m,c,plm)
% This works only if:
% - rank(contrast) > 1
% - number of variance groups = 1
%
% Inputs:
% M   : design matrix
% psi : regression coefficients
% res : residuals
% plm : a struct with many things as generated by
%       'palm_backend.m' and 'palm_takeargs.m'
%
% Outputs:
% G   : F-statistic.
% df2 : Degrees of freedom 2. df1 is rank(C).

df2 = plm.N-plm.rM{m}(c);
cte = plm.eC{m}{c}/(plm.eC{m}{c}'/(M'*M)*plm.eC{m}{c})*plm.eC{m}{c}';
tmp = zeros(size(psi));
for j = 1:size(cte,2),
    tmp(j,:) = sum(bsxfun(@times,psi,cte(:,j)))';
end
G   = sum(tmp.*psi);
ete = sum(res.^2);
G   = G./ete*df2/plm.rC{m}(c);

% ==============================================================
function [G,df2] = fastv(M,psi,res,m,c,plm)
% This works only if:
% - rank(contrast) = 1
% - number of variance groups > 1
%
% Inputs:
% M   : design matrix
% psi : regression coefficients
% res : residuals
% plm : a struct with many things as generated by
%       'palm_backend.m' and 'palm_takeargs.m'
%
% Outputs:
% G   : Aspin-Welch v statistic.
% df2 : Degrees of freedom 2. df1 is 1.

v = size(res,2);
W = zeros(plm.nVG,v);
den = zeros(1,v);
if plm.evperdat{m}{c},
    r = 1;
    dRmb = zeros(plm.nVG,v);
    cte = zeros(1,v);
    for b = 1:plm.nVG,
        bidx = plm.VG == b;
        dRmb(b,:) = sum(plm.dRm{m}{c}(bidx,:),1);
        W(b,:) = dRmb(b,:)./sum(res(bidx,:).^2,1);
        Mb = sum(M(bidx,:).*M(bidx,:),1);
        cte = cte + Mb.*W(b,:);
        W(b,:) = W(b,:)*sum(bidx);
    end
    for t = 1:v,
        den(t) = 1./(reshape(cte(:,t),[r r]));
    end
    G = psi./sqrt(den);
else
    r = size(M,2);
    dRmb = zeros(plm.nVG,1);
    cte = zeros(r^2,v);
    for b = 1:plm.nVG,
        bidx = plm.VG == b;
        dRmb(b) = sum(plm.dRm{m}{c}(bidx,:),1);
        W(b,:) = dRmb(b)./sum(res(bidx,:).^2,1);
        Mb = M(bidx,:)'*M(bidx,:);
        cte = cte + Mb(:)*W(b,:);
        W(b,:) = W(b,:)*sum(bidx);
    end
    for t = 1:v,
        den(t) = plm.eC{m}{c}'/(reshape(cte(:,t),[r r]))*plm.eC{m}{c};
    end
    G = plm.eC{m}{c}'*psi./sqrt(den);
end

bsum = zeros(1,v);
sW1 = sum(W,1);
for b = 1:plm.nVG,
    bsum = bsum + bsxfun(@rdivide,(1-W(b,:)./sW1).^2,dRmb(b,:));
end
df2 = 1/3./bsum;

% ==============================================================
function [G,df2] = fastg(M,psi,res,m,c,plm)
% This works only if:
% - rank(contrast) > 1
% - number of variance groups > 1
%
% Inputs:
% M   : design matrix
% psi : regression coefficients
% res : residuals
% plm : a struct with many things as generated by
%       'palm_backend.m' and 'palm_takeargs.m'
%
% Outputs:
% G   : Welch v^2 statistic.
% df2 : Degrees of freedom 2. df1 is rank(C).

r = size(M,2);
v = size(res,2);

W    = zeros(plm.nVG,v);
dRmb = zeros(plm.nVG,1);
cte  = zeros(r^2,v);
for b = 1:plm.nVG,
    bidx    = plm.VG == b;
    dRmb(b) = sum(plm.dRm{m}{c}(bidx));
    W(b,:)  = dRmb(b)./sum(res(bidx,:).^2);
    Mb      = M(bidx,:)'*M(bidx,:);
    cte     = cte + Mb(:)*W(b,:);
    W(b,:)  = W(b,:)*sum(bidx);
end

G = zeros(1,v);
for t = 1:v,
    A = psi(:,t)'*plm.eC{m}{c};
    G(t) = A/(plm.eC{m}{c}'/(reshape(cte(:,t),[r r]))* ...
        plm.eC{m}{c})*A'/plm.rC{m}(c);
end

bsum = zeros(1,v);
sW1  = sum(W,1);
for b = 1:plm.nVG,
    bsum = bsum + bsxfun(@rdivide,(1-W(b,:)./sW1).^2,dRmb(b));
end
bsum = bsum/plm.rC{m}(c)/(plm.rC{m}(c)+2);
df2  = 1/3./bsum;
G    = G./(1 + 2*(plm.rC{m}(c)-1).*bsum);

% ==============================================================
% Below are the functions to compute multivariate statistics:
% ==============================================================
function Q = fasttsq(M,psi,res,m,c,plm)
% This works only if:
% - rank(contrast) = 1
% - number of variance groups = 1
% - psi and res are 3D
%
% Inputs:
% M   : design matrix
% psi : regression coefficients
% res : residuals
% plm : a struct with many things as generated by
%       'palm_backend.m' and 'palm_takeargs.m'
%
% Outputs:
% Q    : Hotelling's T^2 statistic.

% Swap dimensions so that dims 1 and 2 are subjects and variables
% leaving the voxels/tests as the 3rd.
res = permute(res,[1 3 2]);
psi = permute(psi,[1 3 2]);

nT  = size(res,3);
df0 = plm.N-plm.rM{m}(c);
S = spr(res)/df0;
if plm.evperdat{m}{c},
    cte1 = psi;
    cte2 = sum(M.*M,1);
else
    cte1 = zeros(nT,size(plm.Dset{m}{c},2));
    for t = 1:nT,
        cte1(t,:) = plm.eC{m}{c}'*psi(:,:,t)*plm.Dset{m}{c};
    end
    cte2 = plm.eC{m}{c}'/(M'*M)*plm.eC{m}{c};
end

Q = zeros(1,nT);
for t = 1:nT,
    Q(1,t) = cte1(t,:)/(plm.Dset{m}{c}'*S(:,:,t)*plm.Dset{m}{c})/cte2*cte1(t,:)';
end

function P = fasttsqp(Q,df2,p)
% P-value for Hotelling's T^2
P = palm_gpval(Q*(df2-p+1)/p/df2,p,df2-p+1);

% ==============================================================
function Q = fastq(M,psi,res,m,c,plm)
% This works only if:
% - rank(contrast) > 1
% - number of variance groups = 1
% - psi and res are 3D
%
% Inputs:
% M   : design matrix
% psi : regression coefficients
% res : residuals
% plm : a struct with many things as generated by
%       'palm_backend.m' and 'palm_takeargs.m'
%
% Outputs:
% Q    : Multivariate (yet scalar) statistic.

% Swap dimensions so that dims 1 and 2 are subjects and variables
% leaving the voxels/tests as the 3rd.
res = permute(res,[1 3 2]);
psi = permute(psi,[1 3 2]);

nT   = size(res,3);
cte2 = plm.eC{m}{c}'/(M'*M)*plm.eC{m}{c};
E    = spr(res);
Q    = zeros(1,nT);
for t = 1:nT,
    cte1   = plm.Dset{m}{c}'*psi(:,:,t)'*plm.eC{m}{c};
    H      = cte1/cte2*cte1';
    Q(1,t) = plm.qfun(plm.Dset{m}{c}'*E(:,:,t)*plm.Dset{m}{c},H);
end

% ==============================================================
function Q = wilks(E,H)
% Wilks' lambda.
Q = det(E)/det(E+H);

function P = wilksp(Q,df1,df2,p)
r = df2-(p-df1+1)/2;
u = (p*df1-2)/4;
cden = (p^2+df1^2-5);
if cden > 0,
    t = sqrt((p^2*df1^2-4)/cden);
else
    t = 1;
end
F = (r*t-2*u)*(1-Q.^(1/t))./(Q.^(1/t)*p*df1);
Fdf1 = p*df1;
Fdf2 = r*t-2*u;
P = palm_gpval(F,Fdf1,Fdf2);

% ==============================================================
function Q = lawley(E,H)
% Lawley-Hotelling's trace.
Q = trace(H/E);

function P = lawleyp(Q,df1,df2,p)
m = (abs(p-df1)-1)/2;
n = (df2-p-1)/2;
s = min(p,df1);
if n > 0,
    b = (p+2*n)*(df1+2*n)/(2*(2*n+1)*(n-1));
    c = (2+(p*df1+2)/(b-1))/(2*n);
    Fdf1 = p*df1;
    Fdf2 = 4+(p*df1+2)/(b-1);
    F = (Q/c)*Fdf2/Fdf1;
else
    Fdf1 = s*(2*m+s+1);
    Fdf2 = 2*(s*n+1);
    F = (Q/s)*Fdf2/Fdf1;
end
P = palm_gpval(F,Fdf1,Fdf2);

% ==============================================================
function Q = pillai(E,H)
% Pillai's trace.
Q = trace(H/(E+H));

function P = pillaip(Q,df1,df2,p)
m = (abs(p-df1)-1)/2;
n = (df2-p-1)/2;
s = min(p,df1);
F = (2*n+s+1)/(2*m+s+1)*(Q./(s-Q));
Fdf1 = s*(2*m+s+1);
Fdf2 = s*(2*n+s+1);
P = palm_gpval(F,Fdf1,Fdf2);

% ==============================================================
function Q = roy_ii(E,H)
% Roy's (ii) largest root (analogous to F).
Q = max(eig(H/E));

function P = roy_iip(Q,df1,df2,p)
Fdf1 = max(p,df1);
Fdf2 = df2-Fdf1+df1;
F = Q*Fdf2/Fdf1;
P = palm_gpval(F,Fdf1,Fdf2);

% ==============================================================
function Q = roy_iii(E,H)
% Roy's (iii) largest root (analogous to R^2).
% No p-vals for this (not even approximate or bound).
Q = max(eig(H/(E+H)));

% ==============================================================
function cc = cca(Y,X,k)
% Do CCA via QR & SVD.
% The ranks of X and Y aren't checked for speed.
% Inputs are assumed to have been mean-centered and be free
% of nuisance (partial CCA) via Y=Rz*Y and X=Rz*X.
% k is the k-th CC (typically we want the 1st).
% Based on the algorithm proposed by:
% Bjorck A, Golub GH. Numerical methods for
% computing angles between linear subspaces.
% Math Comput. 1973;27(123):579-579.
[Qy,~]  = qr(Y,0);
[Qx,~]  = qr(X,0);
[~,D,~] = svd(Qy'*Qx,0);
cc      = max(min(D(k,k),1),0);

% ==============================================================
% Below are the functions to combine statistics:
% ==============================================================
function T = tippett(G,df1,df2)
T = min(palm_gpval(G,df1,df2),[],1);

function P = tippettp(T,nG)
%P = T.^plm.nY;
% Note it can't be simply P = 1-(1-T)^K when implementing
% because precision is lost if the original T is smaller than eps,
% something quite common. Hence the need for the Pascal
% triangle, etc, as done below.
pw  = nG:-1:1;
cf  = pascaltri(nG);
sgn = (-1)*(-1).^pw;
P   = sgn.*cf*bsxfun(@power,T,pw');

% ==============================================================
function T = fisher(G,df1,df2)
T = -2*sum(log(palm_gpval(G,df1,df2)),1);

function P = fisherp(T,nG)
P = palm_gpval(T,-1,2*nG);

% ==============================================================
function T = pearsondavid(G,df1,df2)
T = -2*min(...
    sum(log(palm_gpval(G,df1,df2)),1),...
    sum(log(palm_gcdf(G,df1,df2)),1));

function P = pearsondavidp(T,nG)
P = palm_gpval(T,-1,2*nG);

% ==============================================================
function T = stouffer(G,df1,df2)
T = sum(palm_gtoz(G,df1,df2),1)/sqrt(size(G,1));

function P = stoufferp(T,~)
P = palm_gpval(T,0);

% ==============================================================
function T = wilkinson(G,df1,df2,parma)
T = sum(palm_gpval(G,df1,df2) <= parma);

function P = wilkinsonp(T,nG,parma)
lfac    = palm_factorial(nG);
lalpha  = log(parma);
l1alpha = log(1-parma);
P = zeros(size(T));
for k = 1:nG,
    lp1 = lfac(nG+1) - lfac(k+1) - lfac(nG-k+1);
    lp2 = k*lalpha;
    lp3 = (nG-k)*l1alpha;
    P = P + (k>=T).*exp(lp1+lp2+lp3);
end

% ==============================================================
function T = winer(G,df1,df2)
df2 = bsxfun(@times,ones(size(G)),df2);
cte = sqrt(sum(df2./(df2-2),1));
gp  = palm_gpval(G,df1,df2);
gt  = sign(gp-.5).*sqrt(df2./betainv(2*min(gp,1-gp),df2/2,.5)-df2); % =tinv(gp,df2)
T   = -sum(gt)./cte;

function P = winerp(T,~)
P = palm_gcdf(-T,0);

% ==============================================================
function T = edgington(G,df1,df2)
T = sum(palm_gpval(G,df1,df2),1);

function P = edgingtonp(T,nG)
lfac = palm_factorial(nG);
fT   = floor(T);
mxfT = max(fT(:));
P = zeros(size(T));
for j = 0:mxfT,
    p1  = (-1)^j;
    lp2 = - lfac(j+1) - lfac(nG-j+1);
    lp3 = nG*log(T-j);
    P = P + (j<=fT).*p1.*exp(lp2+lp3);
end

% ==============================================================
function T = mudholkargeorge(G,df1,df2)
nG = size(G,1);
mhcte = sqrt(3*(5*nG+4)/nG/(5*nG+2))/pi;
T = mhcte*sum(log(...
    palm_gcdf(G,df1,df2)./...
    palm_gpval(G,df1,df2)),1);

function P = mudholkargeorgep(T,nG)
P = palm_gcdf(T,1,5*nG+4);

% ==============================================================
function [T,Gpval] = fristonnichols(G,df1,df2)
Gpval = palm_gpval(G,df1,df2);
T = max(Gpval,[],1);

function P = fristonp(T,nG,parmu)
P = T.^(nG - parmu + 1);

function T = nicholsp(T,~)
% T itself is P, so there is nothing to do.

% ==============================================================
function T = darlingtonhayes(G,df1,df2,parmr)
df2     = bsxfun(@times,ones(size(G)),df2);
[~,tmp] = sort(G,1,'descend');
[~,tmp] = sort(tmp);
idx     = tmp <= parmr;
G       = reshape(G(idx),horzcat(parmr,size(G,2)));
df2     = reshape(df2(idx),horzcat(parmr,size(df2,2)));
P       = palm_gcdf(G,df1,df2);
Z       = erfinv(2*P-1)*sqrt(2);
T       = mean(Z,1);

% ==============================================================
function T = zaykin(G,df1,df2,parma)
P = -log10(palm_gpval(G,df1,df2));
P(P < -log10(parma)) = 0;
T = sum(P,1);

function P = zaykinp(T,nG,parma)
lT      = -T;
lfac    = palm_factorial(nG);
lalpha  = log10(parma);
l1alpha = log10(1-parma);
P = zeros(size(lT));
for k = 1:plm.nY,
    lp1 = lfac(plm.nY+1) - lfac(k+1) - lfac(plm.nY-k+1);
    lp2 = (plm.nY-k)*l1alpha;
    Tsmall = lT <= k*lalpha;
    Tlarge = ~ Tsmall;
    p3 = 0;
    lnum = log10(k*lalpha - lT(Tsmall));
    for j = 1:k,
        p3 = p3 + 10.^(lT(Tsmall) + (j-1).*lnum - lfac(j));
    end
    lp3small = log10(p3);
    lp3large = k*lalpha;
    P(Tsmall) = P(Tsmall) + 10.^(lp1 + lp2 + lp3small);
    P(Tlarge) = P(Tlarge) + 10.^(lp1 + lp2 + lp3large);
end

% ==============================================================
function T = dudbridgekoeleman(G,df1,df2,parmr)
df2     = bsxfun(@times,ones(size(G)),df2);
[~,tmp] = sort(G,1,'descend');
[~,tmp] = sort(tmp);
idx     = tmp <= parmr;
G       = reshape(G(idx),horzcat(parmr,size(G,2)));
df2     = reshape(df2(idx),horzcat(parmr,size(df2,2)));
P       = -log10(palm_gpval(G,df1,df2));
T       = sum(P,1);

function P = dudbridgekoelemanp(T,nG,parmr)
lT = -T;
lfac = palm_factorial(nG);
P    = zeros(size(lT));
lp1  = lfac(nG+1)  - ...
    lfac(parmr+2)  - ...
    lfac(nG-parmr) + ...
    log10(parmr+2);
for v = 1:numel(lT);
    P(v) = quad(@(t)dkint(t,lp1,lT(v),nG,...
        parmr,lfac(1:parmr)),eps,1);
end

% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
function T = dudbridgekoeleman2(G,df1,df2,parmr,parma)
df2 = bsxfun(@times,ones(size(G)),df2);
P = -log10(palm_gpval(G,df1,df2));
[~,tmp] = sort(G,1,'descend');
[~,tmp] = sort(tmp);
P(tmp > parmr) = 0;
P(P < -log10(parma)) = 0;
T = sum(P,1);

function P = dudbridgekoeleman2p(T,nG,parmr,parma)
lT = -T;
lfac = palm_factorial(nG);
P    = zeros(1,size(T,2));
for k = 1:parmr,
    kk = (nG-k)*log(1-parma);
    if isnan(kk), kk = 0; end
    p1 = exp(lfac(nG+1) - lfac(k+1) - lfac(nG-k+1) + kk);
    p2 = awtk(lT,parma,k,lfac(1:k));
    P = P + p1.*p2;
end
if k < nG,
    lp1 = lfac(nG+1)   - ...
        lfac(parmr+2)  - ...
        lfac(nG-parmr) + ...
        log(parmr+2);
    for v = 1:numel(lT);
        P(v) = P(v) + ...
            quad(@(t)dkint(t,lp1,lT(v),nG,parmr, ...
            lfac(1:parmr)),eps,parma);
    end
end

% - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
function q = dkint(t,lp1,lT,K,r,lfac)
lp2 = (K-r-1).*log(1-t);
ltr = r.*log(t);
L1  = real(lp1 + lp2 + ltr);
s1  = (lT > ltr).*exp(L1);
j   = (1:r)';
lp3 = lT + (j-1)*log(r*log(t)-lT) ...
    - repmat(lfac(j),[1 numel(t)]);
L2  = real(lp1 + repmat(lp2,[r 1]) + lp3);
s2  = (lT <= ltr).*sum(exp(L2));
q   = s1 + s2;

function A = awtk(lw,t,k,lfac)
ltk = k.*log(t);
tk = real(exp(ltk));
s = (1:k)';
L = bsxfun(@plus,lw,...
    bsxfun(@minus,(s-1)*log(k*log(t)-lw),lfac(s)));
S = sum(real(exp(L)),1);
A = (lw <= ltk).*S + (lw > ltk).*tk;

% ==============================================================
function T = taylortibshirani(G,df1,df2)
nG = size(G,1);
P = palm_gpval(G,df1,df2);
[~,tmp] = sort(P);
[~,prank] = sort(tmp);
T = sum(1-P.*(nG+1)./prank)/nG;

function P = taylortibshiranip(T,nG)
P = palm_gcdf(-T./sqrt(nG),0);

% ==============================================================
function T = jiang(G,df1,df2,parma)
nG = size(G,1);
P = palm_gpval(G,df1,df2);
[~,tmp] = sort(P);
[~,prank] = sort(tmp);
T = sum((P<=parma).*(1-P.*(nG+1)./prank))/nG;

% ==============================================================
% Other useful functions:
% ==============================================================
function padj = fastfdr(pval)
% Compute FDR-adjusted p-values

V = numel(pval);
[pval,oidx] = sort(pval);
[~,oidxR]   = sort(oidx);
padj = zeros(size(pval));
prev = 1;
for i = V:-1:1,
    padj(i) = min(prev,pval(i)*V/i);
    prev = padj(i);
end
padj = padj(oidxR);

% ==============================================================
function savedof(df1,df2,fname)
% Save the degrees of freedom.
% This is faster than dlmwrite.

fdof = fopen(fname,'w');
fprintf(fdof,'%g\n',df1);
fprintf(fdof,'%g,',df2);
fseek(fdof,-1,'cof');
fprintf(fdof,'\n');
fclose(fdof);

% ==============================================================
function S = spr(X)
% Compute the matrix with the sum of products.
% X is a 3D array, with the resilduals of the GLM.
% - 1st dimension are the subjects
% - 2nd dimension the modalities.
% - 3rd dimension would tipically be voxels
%
% S is the sum of products that make up the covariance
% matrix:
% - 1st and 3rd dimension have the same size as the number of
%   modalities and the 2nd dimension are typically the voxels.

% To make it faster, the check should be made just once, and
% the result kept throughout runs.
persistent useway1;
if isempty(useway1),
    
    % Test both ways and compute the timings.
    tic; S1 = way1(X); w1 = toc;
    tic; S2 = way2(X); w2 = toc;
    
    % The variables sp1 and sp2 should be absolutely
    % identical but they may have sightly different numerical
    % precisions so to be consistent, choose the same that will
    % be used for all permutations later
    if w1 < w2,
        useway1 = true;
        S = S1;
    else
        useway1 = false;
        S = S2;
    end
else
    if useway1,
        S = way1(X);
    else
        S = way2(X);
    end
end

function sp = way1(X)
% Way 1: this tends to be faster for Octave and if
% the number of levels in X is smaller than about 5.
[~,nY,nT] = size(X);
sp = zeros(nY,nY,nT);
for y1 = 1:nY,
    for y2 = 1:y1,
        sp(y1,y2,:) = sum(X(:,y1,:).*X(:,y2,:),1);
        if y1 ~= y2,
            sp(y2,y1,:) = sp(y1,y2,:);
        end
    end
end

function sp = way2(X)
% Way 2: This tends to be faster in Matlab or if
% there are many levels in X, e.g., more than about 7.
[~,nY,nT] = size(X);
sp = zeros(nY,nY,nT);
for t = 1:nT,
    sp(:,:,t) = (X(:,:,t)'*X(:,:,t));
end


% ==============================================================
function C = pascaltri(K)
% Returns the coefficients for a binomial expansion of
% power K, except the last term. This is used by the Tippett
% method to avoid issues with numerical precision.

persistent Cp;
if isempty(Cp),
    K = K + 1;
    if K <= 2,
        Cp = horzcat(ones(1,K),0);
    elseif K >= 3,
        Rprev = [1 1 0];
        for r = 3:K,
            Cp = horzcat(Rprev + fliplr(Rprev),0);
            Rprev = Cp;
        end
    end
end
C = Cp(1:end-2);

% Finished! :-)
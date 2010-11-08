function gpcf = gpcf_matern52(varargin)
%GPCF_MATERN52	Create a  Matern nu=5/2 covariance function
%
%  Description
%    GPCF = GPCF_MATERN52('PARAM1',VALUE1,'PARAM2,VALUE2,...) 
%    creates Matern nu=5/2 covariance function structure in which
%    the named parameters have the specified values. Any
%    unspecified parameters are set to default values.
%
%    GPCF = GPCF_MATERN52(GPCF,'PARAM1',VALUE1,'PARAM2,VALUE2,...) 
%    modify a covariance function structure with the named
%    parameters altered with the specified values.
%  
%    Parameters for Matern nu=5/2 covariance function [default]
%      magnSigma2        - magnitude (squared) [0.1]
%      lengthScale       - length scale for each input. [1]
%                          This can be either scalar corresponding
%                          to an isotropic function or vector
%                          defining own length-scale for each input
%                          direction.
%      magnSigma2_prior  - prior for magnSigma2  [prior_sqrtunif]
%      lengthScale_prior - prior for lengthScale [prior_unif]
%      metric            - metric structure used by the covariance function []
%      selectedVariables - vector defining which inputs are used [all]
%                          selectedVariables is shorthand for using
%                          metric_euclidean with corresponding components
%
%    Note! If the prior is 'prior_fixed' then the parameter in
%    question is considered fixed and it is not handled in
%    optimization, grid integration, MCMC etc.
%
%  See also
%    GP_SET, GPCF_*, PRIOR_*, METRIC_*

% Copyright (c) 2007-2010 Jarno Vanhatalo
% Copyright (c) 2010 Aki Vehtari

% This software is distributed under the GNU General Public
% License (version 2 or later); please refer to the file
% License.txt, included with the software, for details.

  if nargin>0 && ischar(varargin{1}) && ismember(varargin{1},{'init' 'set'})
    % remove init and set
    varargin(1)=[];
  end
  
  ip=inputParser;
  ip.FunctionName = 'GPCF_MATERN52';
  ip.addOptional('gpcf', [], @isstruct);
  ip.addParamValue('magnSigma2',0.1, @(x) isscalar(x) && x>0);
  ip.addParamValue('lengthScale',1, @(x) isvector(x) && all(x>0));
  ip.addParamValue('metric',[], @isstruct);
  ip.addParamValue('magnSigma2_prior', prior_sqrtunif(), ...
                   @(x) isstruct(x) || isempty(x));
  ip.addParamValue('lengthScale_prior',prior_unif(), ...
                   @(x) isstruct(x) || isempty(x));
  ip.addParamValue('selectedVariables',[], @(x) isempty(x) || ...
                   (isvector(x) && all(x>0)));
  ip.parse(varargin{:});
  gpcf=ip.Results.gpcf;
  
  if isempty(gpcf)
    init=true;
    gpcf.type = 'gpcf_matern52';
  else
    if ~isfield(gpcf,'type') && ~isequal(gpcf.type,'gpcf_matern52')
      error('First argument does not seem to be a valid covariance function structure')
    end
    init=false;
  end
  if init
    % Set the function handles to the nested functions
    gpcf.fh.pak = @gpcf_matern52_pak;
    gpcf.fh.unpak = @gpcf_matern52_unpak;
    gpcf.fh.e = @gpcf_matern52_e;
    gpcf.fh.ghyper = @gpcf_matern52_ghyper;
    gpcf.fh.ginput = @gpcf_matern52_ginput;
    gpcf.fh.cov = @gpcf_matern52_cov;
    gpcf.fh.trcov  = @gpcf_matern52_trcov;
    gpcf.fh.trvar  = @gpcf_matern52_trvar;
    gpcf.fh.recappend = @gpcf_matern52_recappend;
  end
  
  % Initialize parameters
  if init || ~ismember('lengthScale',ip.UsingDefaults)
    gpcf.lengthScale = ip.Results.lengthScale;
  end
  if init || ~ismember('magnSigma2',ip.UsingDefaults)
    gpcf.magnSigma2 = ip.Results.magnSigma2;
  end

  % Initialize prior structure
  if init
    gpcf.p=[];
  end
  if init || ~ismember('lengthScale_prior',ip.UsingDefaults)
    gpcf.p.lengthScale=ip.Results.lengthScale_prior;
  end
  if init || ~ismember('magnSigma2_prior',ip.UsingDefaults)
    gpcf.p.magnSigma2=ip.Results.magnSigma2_prior;
  end

  %Initialize metric
  if ~ismember('metric',ip.UsingDefaults)
    if ~isempty(ip.Results.metric)
      gpcf.metric = ip.Results.metric;
      gpcf = rmfield(gpcf, 'lengthScale');
      gpcf.p = rmfield(gpcf.p, 'lengthScale');
    elseif isfield(gpcf,'metric')
      if ~isfield(gpcf,'lengthScale')
        gpcf.lengthScale = gpcf.metric.lengthScale;
      end
      if ~isfield(gpcf.p,'lengthScale')
        gpcf.p.lengthScale = gpcf.metric.p.lengthScale;
      end
      gpcf = rmfield(gpcf, 'metric');
    end
  end
  
  % selectedVariables options implemented using metric_euclidean
  if ~ismember('selectedVariables',ip.UsingDefaults)
    if ~isfield(gpcf,'metric')
      if ~isempty(ip.Results.selectedVariables)
        gpcf.metric=metric_euclidean('components',...
                                     num2cell(ip.Results.selectedVariables),...
                                     'lengthScale',gpcf.lengthScale,...
                                     'lengthScale_prior',gpcf.p.lengthScale);
        gpcf = rmfield(gpcf, 'lengthScale');
        gpcf.p = rmfield(gpcf.p, 'lengthScale');
      end
    elseif isfield(gpcf,'metric') 
      if ~isempty(ip.Results.selectedVariables)
        gpcf.metric=metric_euclidean(gpcf.metric,...
                                     'components',...
                                     num2cell(ip.Results.selectedVariables));
        if ~ismember('lengthScale',ip.UsingDefaults)
          gpcf.metric.lengthScale=ip.Results.lengthScale;
          gpcf = rmfield(gpcf, 'lengthScale');
        end
        if ~ismember('lengthScale_prior',ip.UsingDefaults)
          gpcf.metric.p.lengthScale=ip.Results.lengthScale_prior;
          gpcf.p = rmfield(gpcf.p, 'lengthScale');
        end
      else
        if ~isfield(gpcf,'lengthScale')
          gpcf.lengthScale = gpcf.metric.lengthScale;
        end
        if ~isfield(gpcf.p,'lengthScale')
          gpcf.p.lengthScale = gpcf.metric.p.lengthScale;
        end
        gpcf = rmfield(gpcf, 'metric');
      end
    end
  end

  function w = gpcf_matern52_pak(gpcf, w)
  %GPCF_MATERN52_PAK  Combine GP covariance function hyper-parameters
  %                   into one vector.
  %
  %  Description
  %    W = GPCF_MATERN52_PAK(GPCF) takes a covariance function data
  %    structure GPCF and combines the covariance function
  %    parameters and their hyperparameters into a single row
  %    vector W and takes a logarithm of the covariance function
  %    parameters.
  %
  %       w = [ log(gpcf.magnSigma2)
  %             (hyperparameters of gpcf.magnSigma2) 
  %             log(gpcf.lengthScale(:))
  %             (hyperparameters of gpcf.lengthScale)]'
  %
  %  See also
  %    GPCF_MATERN52_UNPAK

    w = [];
    
    if ~isempty(gpcf.p.magnSigma2)
      w = [w log(gpcf.magnSigma2)];
      % Hyperparameters of magnSigma2
      w = [w feval(gpcf.p.magnSigma2.fh.pak, gpcf.p.magnSigma2)];
    end        
    
    if isfield(gpcf,'metric')
      w = [w feval(gpcf.metric.fh.pak, gpcf.metric)];
    else
      if ~isempty(gpcf.p.lengthScale)
        w = [w log(gpcf.lengthScale)];
        % Hyperparameters of lengthScale
        w = [w feval(gpcf.p.lengthScale.fh.pak, gpcf.p.lengthScale)];
      end
    end
    
  end

  function [gpcf, w] = gpcf_matern52_unpak(gpcf, w)
  %GPCF_MATERN52_UNPAK  Sets the covariance function parameters
  %                     into the structure
  %
  %  Description
  %    [GPCF, W] = GPCF_MATERN52_UNPAK(GPCF, W) takes a covariance
  %    function data structure GPCF and a hyper-parameter vector W,
  %    and returns a covariance function data structure identical to
  %    the input, except that the covariance hyper-parameters have
  %    been set to the values in W. Deletes the values set to GPCF
  %    from W and returns the modified W.
  %
  %    Assignment is inverse of  
  %       w = [ log(gpcf.magnSigma2)
  %             (hyperparameters of gpcf.magnSigma2)
  %             log(gpcf.lengthScale(:))
  %             (hyperparameters of gpcf.lengthScale)]'
  %
  %  See also
  %    GPCF_MATERN52_PAK
    
    gpp=gpcf.p;
    if ~isempty(gpp.magnSigma2)
      gpcf.magnSigma2 = exp(w(1));
      w = w(2:end);
      % Hyperparameters of magnSigma2
      [p, w] = feval(gpcf.p.magnSigma2.fh.unpak, gpcf.p.magnSigma2, w);
      gpcf.p.magnSigma2 = p;
    end
    
    if isfield(gpcf,'metric')
      [metric, w] = feval(gpcf.metric.fh.unpak, gpcf.metric, w);
      gpcf.metric = metric;
    else            
      if ~isempty(gpp.lengthScale)
        i1=1;
        i2=length(gpcf.lengthScale);
        gpcf.lengthScale = exp(w(i1:i2));
        w = w(i2+1:end);
        % Hyperparameters of lengthScale
        [p, w] = feval(gpcf.p.lengthScale.fh.unpak, gpcf.p.lengthScale, w);
        gpcf.p.lengthScale = p;
      end
    end
    
  end
  
  function eprior =gpcf_matern52_e(gpcf, x, t)
  %GPCF_MATERN52_E  Evaluate the energy of prior of MATERN52 parameters
  %
  %  Description
  %    E = GPCF_MATERN52_E(GPCF, X, T) takes a covariance function
  %    data structure GPCF together with a matrix X of input
  %    vectors and a vector T of target vectors and evaluates log
  %    p(th) x J, where th is a vector of MATERN52 parameters and J
  %    is the Jacobian of transformation exp(w) = th. (Note that
  %    the parameters are log transformed, when packed.)
  %
  %    Also the log prior of the hyperparameters of the covariance
  %    function parameters is added to E if hyper-hyperprior is
  %    defined.
  %
  %  See also
  %    GPCF_MATERN52_PAK, GPCF_MATERN52_UNPAK, GPCF_MATERN52_G, GP_E
  %

  % Evaluate the prior contribution to the error. The parameters that
  % are sampled are transformed, e.g., W = log(w) where w is all
  % the "real" samples. On the other hand errors are evaluated in
  % the W-space so we need take into account also the Jacobian of
  % transformation, e.g., W -> w = exp(W). See Gelman et.al., 2004,
  % Bayesian data Analysis, second edition, p24.
    eprior = 0;
    gpp=gpcf.p;
    
    [n, m] =size(x);

    if ~isempty(gpcf.p.magnSigma2)
      eprior = eprior + feval(gpp.magnSigma2.fh.e, gpcf.magnSigma2, ...
                              gpp.magnSigma2) - log(gpcf.magnSigma2);
    end
      
    if isfield(gpcf,'metric')            
      eprior = eprior + feval(gpcf.metric.fh.e, gpcf.metric, x, t);
    elseif ~isempty(gpp.lengthScale)
      eprior = eprior + feval(gpp.lengthScale.fh.e, gpcf.lengthScale, ...
                              gpp.lengthScale) - sum(log(gpcf.lengthScale));
    end
  end
  
  function [DKff, gprior]  = gpcf_matern52_ghyper(gpcf, x, x2, mask)
  %GPCF_MATERN52_GHYPER  Evaluate gradient of covariance function and 
  %                      hyper-prior with respect to the hyperparameters.
  %
  %  Description
  %    [DKff, GPRIOR] = GPCF_MATERN52_GHYPER(GPCF, X) takes a
  %    covariance function data structure GPCF, a matrix X of input
  %    vectors and returns DKff, the gradients of covariance matrix
  %    Kff = k(X,X) with respect to th (cell array with matrix
  %    elements), and GPRIOR = d log (p(th))/dth, where th is the
  %    vector of hyperparameters
  %
  %    [DKff, GPRIOR] = GPCF_MATERN52_GHYPER(GPCF, X, X2) takes a
  %    covariance function data structure GPCF, a matrix X of input
  %    vectors and returns DKff, the gradients of covariance matrix
  %    Kff = k(X,X2) with respect to th (cell array with matrix
  %    elements), and GPRIOR = d log (p(th))/dth, where th is the
  %    vector of hyperparameters
  %
  %    [DKff, GPRIOR] = GPCF_MATERN52_GHYPER(GPCF, X, [], MASK)
  %    takes a covariance function data structure GPCF, a matrix X
  %    of input vectors and returns DKff, the diagonal of gradients
  %    of covariance matrix Kff = k(X,X2) with respect to th (cell
  %    array with matrix elements), and GPRIOR = d log (p(th))/dth,
  %    where th is the vector of hyperparameters. This is needed
  %    for example with FIC sparse approximation.
  %
  %  See also
  %    GPCF_MATERN52_PAK, GPCF_MATERN52_UNPAK, GPCF_MATERN52_E, GP_G

    gpp=gpcf.p;
    [n, m] =size(x);

    i1=0;i2=1;
    DKff = {};
    gprior = [];

    % Evaluate: DKff{1} = d Kff / d magnSigma2
    %           DKff{2} = d Kff / d lengthScale
    % NOTE! Here we have already taken into account that the parameters
    % are transformed through log() and thus dK/dlog(p) = p * dK/dp
    % evaluate the gradient for training covariance
    if nargin == 2
      Cdm = gpcf_matern52_trcov(gpcf, x);

      ii1=0;
      if ~isempty(gpcf.p.magnSigma2)
        ii1 = ii1 +1;
        DKff{ii1} = Cdm;
      end

      if isfield(gpcf,'metric')
        dist = feval(gpcf.metric.fh.distance, gpcf.metric, x);
        [gdist, gprior_dist] = feval(gpcf.metric.fh.ghyper, gpcf.metric, x);
        ma2 = gpcf.magnSigma2;
        for i=1:length(gdist)
          ii1 = ii1+1;
          DKff{ii1} = ma2.*(sqrt(5) + 10.*dist./3).*gdist{i}.*exp(-sqrt(5).*dist);
          DKff{ii1} = DKff{ii1} - ma2.*(1+sqrt(5).*dist+5.*dist.^2./3).*exp(-sqrt(5).*dist).*sqrt(5).*gdist{i};
        end
      else
        if ~isempty(gpcf.p.lengthScale)
          ma2 = gpcf.magnSigma2;
          % loop over all the lengthScales
          if length(gpcf.lengthScale) == 1
            % In the case of isotropic MATERN52
            s = 1./gpcf.lengthScale;
            dist = 0;
            for i=1:m
              dist = dist + bsxfun(@minus,x(:,i),x(:,i)').^2;
            end
            D = ma2./3.*(5.*dist.*s^2 + 5.*sqrt(5.*dist).*dist.*s.^3).*exp(-sqrt(5.*dist).*s);
            ii1 = ii1+1;
            DKff{ii1} = D;
          else
            % In the case ARD is used
            s = 1./gpcf.lengthScale.^2;
            dist = 0;
            for i=1:m
              dist = dist + s(i).*(bsxfun(@minus,x(:,i),x(:,i)')).^2;
            end
            dist=sqrt(dist);
            for i=1:m
              D = ma2.*s(i).*((5+5.*sqrt(5).*dist)/3).*(bsxfun(@minus,x(:,i),x(:,i)')).^2.*exp(-sqrt(5).*dist);
              
              ii1 = ii1+1;
              DKff{ii1} = D;
            end
          end
        end
      end
      % Evaluate the gradient of non-symmetric covariance (e.g. K_fu)
    elseif nargin == 3
      if size(x,2) ~= size(x2,2)
        error('gpcf_matern52 -> _ghyper: The number of columns in x and x2 has to be the same. ')
      end

      ii1=0;
      K = feval(gpcf.fh.cov, gpcf, x, x2);
      if ~isempty(gpcf.p.magnSigma2)
        ii1 = ii1 +1;
        DKff{ii1} = K;
      end
      
      if isfield(gpcf,'metric')                
        dist = feval(gpcf.metric.fh.distance, gpcf.metric, x, x2);
        [gdist, gprior_dist] = feval(gpcf.metric.fh.ghyper, gpcf.metric, x, x2);
        for i=1:length(gdist)
          ii1 = ii1+1;
          ma2 = gpcf.magnSigma2;
          DKff{ii1} = ma2.*(sqrt(5) + 10.*dist./3).*gdist{i}.*exp(-sqrt(5).*dist);
          DKff{ii1} = DKff{ii1} - ma2.*(1+sqrt(5).*dist+5.*dist.^2./3).*exp(-sqrt(5).*dist).*sqrt(5).*gdist{i};
        end
      else
        if ~isempty(gpcf.p.lengthScale)
          % Evaluate help matrix for calculations of derivatives with respect
          % to the lengthScale
          if length(gpcf.lengthScale) == 1
            % In the case of an isotropic matern52
            s = 1./gpcf.lengthScale;
            ma2 = gpcf.magnSigma2;
            dist = 0; 
            for i=1:m
              dist = dist + bsxfun(@minus,x(:,i),x2(:,i)').^2;
            end
            DK = ma2./3.*(5.*dist.*s^2 + 5.*sqrt(5.*dist).*dist.*s.^3).*exp(-sqrt(5.*dist).*s);
            ii1 = ii1+1;
            DKff{ii1} = DK;
          else
            % In the case ARD is used
            s = 1./gpcf.lengthScale.^2;
            ma2 = gpcf.magnSigma2;
            dist = 0;
            for i=1:m
              dist = dist + s(i).*(bsxfun(@minus,x(:,i),x2(:,i)')).^2;
            end
            for i=1:m
              D1 = ma2.*exp(-sqrt(5.*dist)).*s(i).*(bsxfun(@minus,x(:,i),x2(:,i)')).^2;;
              DK = (5./3 + 5.*sqrt(5.*dist)/3).*D1;
              ii1=ii1+1;
              DKff{ii1} = DK;
            end     
          end
        end
      end
      % Evaluate: DKff{1}    = d mask(Kff,I) / d magnSigma2
      %           DKff{2...} = d mask(Kff,I) / d lengthScale
    elseif nargin == 4
      ii1=0;
      
      if ~isempty(gpcf.p.magnSigma2)
        ii1 = ii1+1;
        DKff{ii1} = feval(gpcf.fh.trvar, gpcf, x);   % d mask(Kff,I) / d magnSigma2
      end
      if isfield(gpcf,'metric')
        dist = 0;
        [gdist, gprior_dist] = feval(gpcf.metric.fh.ghyper, gpcf.metric, x, [], 1);
        for i=1:length(gdist)
          ii1 = ii1+1;
          DKff{ii1} = 0;
        end
      else
        if ~isempty(gpcf.p.lengthScale)
          for i2=1:length(gpcf.lengthScale)
            ii1 = ii1+1;
            DKff{ii1}  = 0; % d mask(Kff,I) / d lengthScale
          end
        end
      end
    end

    if nargout > 1
      ggs = [];
      i1=0;
      if ~isempty(gpcf.p.magnSigma2)            
        % Evaluate the gprior with respect to magnSigma2
        i1 = i1+1;
        ggs = feval(gpp.magnSigma2.fh.g, gpcf.magnSigma2, gpp.magnSigma2);
        gprior = ggs(i1).*gpcf.magnSigma2 - 1;
      end
      
      if isfield(gpcf,'metric')
        % Evaluate the data contribution of gradient with respect to
        % lengthScale
        for i2=1:length(gprior_dist)
          i1 = i1+1;                    
          gprior(i1)=gprior_dist(i2);
        end
      else
        if ~isempty(gpcf.p.lengthScale)
          i1=i1+1; 
          lll = length(gpcf.lengthScale);
          gg = feval(gpp.lengthScale.fh.g, gpcf.lengthScale, gpp.lengthScale);
          gprior(i1:i1-1+lll) = gg(1:lll).*gpcf.lengthScale - 1;
          gprior = [gprior gg(lll+1:end)];
        end
      end
      if length(ggs) > 1
        gprior = [gprior ggs(2:end)];
      end
    end
  end
  
  function [DKff, gprior]  = gpcf_matern52_ginput(gpcf, x, x2)
  %GPCF_MATERN52_GINPUT  Evaluate gradient of covariance function with 
  %                      respect to x.
  %
  %  Description
  %    DKff = GPCF_MATERN52_GHYPER(GPCF, X) takes a covariance
  %    function data structure GPCF, a matrix X of input vectors
  %    and returns DKff, the gradients of covariance matrix Kff =
  %    k(X,X) with respect to X (cell array with matrix elements)
  %
  %    DKff = GPCF_MATERN52_GHYPER(GPCF, X, X2) takes a covariance
  %    function data structure GPCF, a matrix X of input vectors
  %    and returns DKff, the gradients of covariance matrix Kff =
  %    k(X,X2) with respect to X (cell array with matrix elements).
  %
  %  See also
  %    GPCF_MATERN52_PAK, GPCF_MATERN52_UNPAK, GPCF_MATERN52_E, GP_G

    [n, m] =size(x);
    ma2 = gpcf.magnSigma2;
    ii1 = 0;
    if nargin == 2
      if isfield(gpcf,'metric')
        K = feval(gpcf.fh.trcov, gpcf, x);
        dist = feval(gpcf.metric.fh.distance, gpcf.metric, x);
        gdist = feval(gpcf.metric.fh.ginput, gpcf.metric, x);
        for i=1:length(gdist)
          ii1 = ii1+1;
          ma2 = gpcf.magnSigma2;
          DKff{ii1} = ma2.*(sqrt(5) + 10.*dist./3).*gdist{i}.*exp(-sqrt(5).*dist);
          DKff{ii1} = DKff{ii1} - ma2.*(1+sqrt(5).*dist+5.*dist.^2./3).*exp(-sqrt(5).*dist).*sqrt(5).*gdist{i};
        end
      else
        if length(gpcf.lengthScale) == 1
          % In the case of an isotropic
          s = repmat(1./gpcf.lengthScale.^2, 1, m);
        else
          s = 1./gpcf.lengthScale.^2;
        end
        dist=0;
        for i2=1:m
          dist = dist + s(i2).*(bsxfun(@minus,x(:,i2),x(:,i2)')).^2;
        end
        dist=sqrt(dist);
        for i=1:m
          for j = 1:n
            D1 = zeros(n,n);
            D1(j,:) = sqrt(s(i)).*bsxfun(@minus,x(j,i),x(:,i)');
            D1 = D1 + D1';
            DK = ma2.*(10/3 - 5 - 5.*sqrt(5).*dist./3).*exp(-sqrt(5).*dist).*D1;                    
            
            ii1 = ii1 + 1;
            DKff{ii1} = DK;
          end
        end
      end
    elseif nargin == 3
      if isfield(gpcf,'metric')
        K = feval(gpcf.fh.cov, gpcf, x, x2);
        dist = feval(gpcf.metric.fh.distance, gpcf.metric, x, x2);
        gdist = feval(gpcf.metric.fh.ginput, gpcf.metric, x, x2);
        ma2 = gpcf.magnSigma2;
        for i=1:length(gdist)
          ii1 = ii1+1;
          DKff{ii1} = ma2.*(sqrt(5) + 10.*dist./3).*gdist{i}.*exp(-sqrt(5).*dist);
          DKff{ii1} = DKff{ii1} - ma2.*(1+sqrt(5).*dist+5.*dist.^2./3).*exp(-sqrt(5).*dist).*sqrt(5).*gdist{i};
        end
      else
        [n2, m2] =size(x2);
        if length(gpcf.lengthScale) == 1
          s = repmat(1./gpcf.lengthScale.^2, 1, m);
        else
          s = 1./gpcf.lengthScale.^2;
        end
        dist=0; 
        for i2=1:m
          dist = dist + s(i2).*(bsxfun(@minus,x(:,i2),x2(:,i2)')).^2;
        end
        dist=sqrt(dist);
        ii1 = 0;
        for i=1:m
          for j = 1:n
            D1 = zeros(n,n2);
            D1(j,:) = sqrt(s(i)).*bsxfun(@minus,x(j,i),x2(:,i)');
            DK = ma2.*(10/3 - 5 - 5.*sqrt(5).*dist./3).*exp(-sqrt(5).*dist).*D1;                    
            
            ii1 = ii1 + 1;
            DKff{ii1} = DK;
          end
        end
      end
    end
  end

  function C = gpcf_matern52_cov(gpcf, x1, x2)
  %GP_MATERN52_COV  Evaluate covariance matrix between two input vectors.
  %
  %  Description
  %    C = GP_MATERN52_COV(GP, TX, X) takes in covariance function
  %    of a Gaussian process GP and two matrixes TX and X that
  %    contain input vectors to GP. Returns covariance matrix C. 
  %    Every element ij of C contains covariance between inputs i
  %    in TX and j in X.
  %
  %
  %  See also
  %    GPCF_MATERN52_TRCOV, GPCF_MATERN52_TRVAR, GP_COV, GP_TRCOV
    
    if isempty(x2)
      x2=x1;
    end
    [n1,m1]=size(x1);
    [n2,m2]=size(x2);

    if m1~=m2
      error('the number of columns of X1 and X2 has to be same')
    end

    if isfield(gpcf,'metric')
      ma2 = gpcf.magnSigma2;
      dist = sqrt(5).*feval(gpcf.metric.fh.distance, gpcf.metric, x1, x2);
      dist(dist<eps) = 0;
      C = ma2.*(1 + dist + dist.^2./3).*exp(-dist);
      C(C<eps)=0;
    else
      C=zeros(n1,n2);
      ma2 = gpcf.magnSigma2;
      
      % Evaluate the covariance
      if ~isempty(gpcf.lengthScale)
        s2 = 1./gpcf.lengthScale.^2;
        % If ARD is not used make s a vector of
        % equal elements
        if size(s2)==1
          s2 = repmat(s2,1,m1);
        end
        dist2=zeros(n1,n2);
        for j=1:m1
          dist2 = dist2 + s2(:,j).*(bsxfun(@minus,x1(:,j),x2(:,j)')).^2;
        end
        dist = sqrt(5.*dist2);
        C = ma2.*(1 + dist + 5.*dist2./3).*exp(-dist);
      end
      C(C<eps)=0;
    end
  end

  function C = gpcf_matern52_trcov(gpcf, x)
  %GP_MATERN52_TRCOV  Evaluate training covariance matrix of inputs.
  %
  %  Description
  %    C = GP_MATERN52_TRCOV(GP, TX) takes in covariance function
  %    of a Gaussian process GP and matrix TX that contains
  %    training input vectors. Returns covariance matrix C. Every
  %    element ij of C contains covariance between inputs i and j
  %    in TX
  %
  %  See also
  %    GPCF_MATERN52_COV, GPCF_MATERN52_TRVAR, GP_COV, GP_TRCOV
    
    if isfield(gpcf,'metric')
      ma2 = gpcf.magnSigma2;
      dist = sqrt(5).*feval(gpcf.metric.fh.distance, gpcf.metric, x);
      C = ma2.*(1 + dist + dist.^2./3).*exp(-dist);
    else
      % Try to use the C-implementation            
      C = trcov(gpcf,x);
      if isnan(C)
        % If there wasn't C-implementation do here
        [n, m] =size(x);
        
        s2 = 1./(gpcf.lengthScale).^2;
        if size(s2)==1
          s2 = repmat(s2,1,m);
        end
        ma2 = gpcf.magnSigma2;
        
        % Here we take advantage of the
        % symmetry of covariance matrix
        C=zeros(n,n);
        for i1=2:n
          i1n=(i1-1)*n;
          for i2=1:i1-1
            ii=i1+(i2-1)*n;
            for i3=1:m
              C(ii)=C(ii)+s2(i3).*(x(i1,i3)-x(i2,i3)).^2;       % the covariance function
            end
            C(i1n+i2)=C(ii);
          end
        end
        dist = sqrt(5.*C);
        C = ma2.*(1 + dist + 5.*C./3).*exp(-dist);
        C(C<eps)=0;
      end
    end
  end

  function C = gpcf_matern52_trvar(gpcf, x)
  %GP_MATERN52_TRVAR  Evaluate training variance vector
  %
  %  Description
  %    C = GP_MATERN52_TRVAR(GPCF, TX) takes in covariance function
  %    of a Gaussian process GPCF and matrix TX that contains
  %    training inputs. Returns variance vector C. Every element i
  %    of C contains variance of input i in TX
  %
  %
  %  See also
  %    GPCF_MATERN52_COV, GP_COV, GP_TRCOV        
    [n, m] =size(x);

    C = ones(n,1).*gpcf.magnSigma2;
    C(C<eps)=0;
  end

  function reccf = gpcf_matern52_recappend(reccf, ri, gpcf)
  %RECAPPEND  Record append
  %
  %  Description
  %    RECCF = GPCF_MATERN52_RECAPPEND(RECCF, RI, GPCF) takes a
  %    covariance function record structure RECCF, record index RI
  %    and covariance function structure GPCF with the current MCMC
  %    samples of the hyperparameters. Returns RECCF which contains
  %    all the old samples and the current samples from GPCF .
  %
  %  See also
  %    GP_MC and GP_MC -> RECAPPEND

  % Initialize record
    if nargin == 2
      reccf.type = 'gpcf_matern52';

      % Initialize parameters
      reccf.lengthScale= [];
      reccf.magnSigma2 = [];

      % Set the function handles
      reccf.fh.pak = @gpcf_matern52_pak;
      reccf.fh.unpak = @gpcf_matern52_unpak;
      reccf.fh.e = @gpcf_matern52_e;
      reccf.fh.g = @gpcf_matern52_g;
      reccf.fh.cov = @gpcf_matern52_cov;
      reccf.fh.trcov  = @gpcf_matern52_trcov;
      reccf.fh.trvar  = @gpcf_matern52_trvar;
      reccf.fh.recappend = @gpcf_matern52_recappend;  
      reccf.p=[];
      reccf.p.lengthScale=[];
      reccf.p.magnSigma2=[];
      if ~isempty(ri.p.lengthScale)
        reccf.p.lengthScale = ri.p.lengthScale;
      end
      if ~isempty(ri.p.magnSigma2)
        reccf.p.magnSigma2 = ri.p.magnSigma2;
      end
      return
    end

    gpp = gpcf.p;

    if ~isfield(gpcf,'metric')
      % record lengthScale
      if ~isempty(gpcf.lengthScale)
        reccf.lengthScale(ri,:)=gpcf.lengthScale;
        reccf.p.lengthScale = feval(gpp.lengthScale.fh.recappend, reccf.p.lengthScale, ri, gpcf.p.lengthScale);
      elseif ri==1
        reccf.lengthScale=[];
      end
    end
    % record magnSigma2
    if ~isempty(gpcf.magnSigma2)
      reccf.magnSigma2(ri,:)=gpcf.magnSigma2;
      reccf.p.magnSigma2 = feval(gpp.magnSigma2.fh.recappend, reccf.p.magnSigma2, ri, gpcf.p.magnSigma2);
    elseif ri==1
      reccf.magnSigma2=[];
    end
  end
end


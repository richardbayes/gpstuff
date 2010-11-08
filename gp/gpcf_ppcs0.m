function gpcf = gpcf_ppcs0(varargin)
%GPCF_PPCS0  Create a piece wise polynomial (q=0) covariance function 
%
%  Description
%    GPCF = GPCF_PPCS0('nin',nin,'PARAM1',VALUE1,'PARAM2,VALUE2,...) 
%    creates piece wise polynomial (q=0) covariance function
%    structure in which the named parameters have the specified
%    values. Any unspecified parameters are set to default values. 
%    Obligatory parameter is 'nin', which tells the dimension
%    of input space.
%  
%    GPCF = GPCF_PPCS0(GPCF,'PARAM1',VALUE1,'PARAM2,VALUE2,...)
%    modify a covariance function structure with the named
%    parameters altered with the specified values.
%
%    Parameters for piece wise polynomial (q=0) covariance function [default]
%      magnSigma2        - magnitude (squared) [0.1]
%      lengthScale       - length scale for each input. [1]
%                          This can be either scalar corresponding
%                          to an isotropic function or vector
%                          defining own length-scale for each input
%                          direction.
%      l_nin             - order of the polynomial [floor(nin/2) + 1]
%                          Has to be greater than or equal to default.
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
%    The piecewise polynomial function is the following:
%
%      k_pp0(x_i, x_j) = ma2*cs^(l)
%
%      where r = sum( (x_i,d - x_j,d).^2./l^2_d )
%            l = floor(l_nin/2) + 1 
%            cs = max(0,1-r);
%      and l_nin must be greater or equal to gpcf.nin
%       
%    NOTE! Use of gpcf_ppcs0 requires that you have installed
%    GPstuff with SuiteSparse.
%
%  See also
%    GP_SET, GPCF_*, PRIOR_*, METRIC_*

% Copyright (c) 2009-2010 Jarno Vanhatalo
% Copyright (c) 2010 Aki Vehtari

% This software is distributed under the GNU General Public
% License (version 2 or later); please refer to the file
% License.txt, included with the software, for details.

  if nargin>0 && ischar(varargin{1}) && ismember(varargin{1},{'init' 'set'})
    % remove init and set
    varargin(1)=[];
  end
  
  ip=inputParser;
  ip.FunctionName = 'GPCF_PPCS0';
  ip.addOptional('gpcf', [], @isstruct);
  ip.addParamValue('nin',[], @(x) isscalar(x) && x>0 && mod(x,1)==0);
  ip.addParamValue('magnSigma2',0.1, @(x) isscalar(x) && x>0);
  ip.addParamValue('lengthScale',1, @(x) isvector(x) && all(x>0));
  ip.addParamValue('l_nin',[], @(x) isscalar(x) && x>0 && mod(x,1)==0);
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
    % Check that SuiteSparse is available
    if ~exist('ldlchol')
      error('SuiteSparse is not installed (or it is not in the path). gpcf_ppcs0 cannot be used!')
    end
    init=true;
    gpcf.nin=ip.Results.nin;
    if isempty(gpcf.nin)
      error('nin has to be given for ppcs: gpcf_ppcs0(''nin'',NIN,...)')
    end
    gpcf.type = 'gpcf_ppcs0';
    % cf is compactly supported
    gpcf.cs = 1;
  else
    if ~isfield(gpcf,'type') && ~isequal(gpcf.type,'gpcf_ppcs0')
      error('First argument does not seem to be a valid covariance function structure')
    end
    init=false;
  end
  if init
    % Set the function handles to the nested functions
    gpcf.fh.pak = @gpcf_ppcs0_pak;
    gpcf.fh.unpak = @gpcf_ppcs0_unpak;
    gpcf.fh.e = @gpcf_ppcs0_e;
    gpcf.fh.ghyper = @gpcf_ppcs0_ghyper;
    gpcf.fh.ginput = @gpcf_ppcs0_ginput;
    gpcf.fh.cov = @gpcf_ppcs0_cov;
    gpcf.fh.trcov  = @gpcf_ppcs0_trcov;
    gpcf.fh.trvar  = @gpcf_ppcs0_trvar;
    gpcf.fh.recappend = @gpcf_ppcs0_recappend;
  end

  % Initialize parameters
  if init || ~ismember('l_nin',ip.UsingDefaults)
    gpcf.l=ip.Results.l_nin;
    if isempty(gpcf.l)
      gpcf.l = floor(gpcf.nin/2) + 2;
    end
    if gpcf.l < gpcf.nin
      error('The l_nin has to be greater than or equal to the number of inputs!')
    end
  end
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
  
  function w = gpcf_ppcs0_pak(gpcf)
  %GPCF_PPCS0_PAK  Combine GP covariance function hyper-parameters into
  %               one vector.
  %
  %  Description
  %    W = GPCF_PPCS0_PAK(GPCF) takes a covariance function data
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
  %    GPCF_PPCS0_UNPAK

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

  function [gpcf, w] = gpcf_ppcs0_unpak(gpcf, w)
  %GPCF_PPCS0_UNPAK  Sets the covariance function parameters into
  %                 the structure
  %
  %  Description
  %    [GPCF, W] = GPCF_PPCS0_UNPAK(GPCF, W) takes a covariance
  %    function data structure GPCF and a hyper-parameter vector W,
  %    and returns a covariance function data structure identical
  %    to the input, except that the covariance hyper-parameters
  %    have been set to the values in W. Deletes the values set to
  %    GPCF from W and returns the modified W.
  %
  %    Assignment is inverse of  
  %       w = [ log(gpcf.magnSigma2)
  %             (hyperparameters of gpcf.magnSigma2)
  %             log(gpcf.lengthScale(:))
  %             (hyperparameters of gpcf.lengthScale)]'
  %
  %  See also
  %    GPCF_PPCS0_PAK

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

  function eprior =gpcf_ppcs0_e(gpcf, x, t)
  %GPCF_PPCS0_E  Evaluate the energy of prior of PPCS0 parameters
  %
  %  Description
  %    E = GPCF_PPCS0_E(GPCF, X, T) takes a covariance function data
  %    structure GPCF together with a matrix X of input vectors and
  %    a vector T of target vectors and evaluates log p(th) x J,
  %    where th is a vector of PPCS0 parameters and J is the
  %    Jacobian of transformation exp(w) = th. (Note that the
  %    parameters are log transformed, when packed.)
  %
  %    Also the log prior of the hyperparameters of the covariance
  %    function parameters is added to E if hyper-hyperprior is
  %    defined.
  %
  %  See also
  %    GPCF_PPCS0_PAK, GPCF_PPCS0_UNPAK, GPCF_PPCS0_G, GP_E

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

  function [DKff, gprior]  = gpcf_ppcs0_ghyper(gpcf, x, x2, mask)
  %GPCF_PPCS0_GHYPER  Evaluate gradient of covariance function and
  %                  hyper-prior with respect to the hyperparameters.
  %
  %  Description
  %    [DKff, GPRIOR] = GPCF_PPCS0_GHYPER(GPCF, X) takes a
  %    covariance function data structure GPCF, a matrix X of input
  %    vectors and returns DKff, the gradients of covariance matrix
  %    Kff = k(X,X) with respect to th (cell array with matrix
  %    elements), and GPRIOR = d log (p(th))/dth, where th is the
  %    vector of hyperparameters
  %
  %    [DKff, GPRIOR] = GPCF_PPCS0_GHYPER(GPCF, X, X2) takes a
  %    covariance function data structure GPCF, a matrix X of input
  %    vectors and returns DKff, the gradients of covariance matrix
  %    Kff = k(X,X2) with respect to th (cell array with matrix
  %    elements), and GPRIOR = d log (p(th))/dth, where th is the
  %    vector of hyperparameters
  %
  %    [DKff, GPRIOR] = GPCF_PPCS0_GHYPER(GPCF, X, [], MASK) takes a
  %    covariance function data structure GPCF, a matrix X of input
  %    vectors and returns DKff, the diagonal of gradients of
  %    covariance matrix Kff = k(X,X2) with respect to th (cell
  %    array with matrix elements), and GPRIOR = d log (p(th))/dth,
  %    where th is the vector of hyperparameters. This is needed
  %    for example with FIC sparse approximation.
  %
  %  See also
  %   GPCF_PPCS0_PAK, GPCF_PPCS0_UNPAK, GPCF_PPCS0_E, GP_G

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
      Cdm = gpcf_ppcs0_trcov(gpcf, x);
      ii1=0;

      if ~isempty(gpcf.p.magnSigma2)
        ii1 = ii1 +1;
        DKff{ii1} = Cdm;
      end
      
      l = gpcf.l;
      [I,J] = find(Cdm);
      
      if isfield(gpcf,'metric')
        % Compute the sparse distance matrix and its gradient.
        ntriplets = (nnz(Cdm)-n)./2;
        I = zeros(ntriplets,1);
        J = zeros(ntriplets,1);
        dist = zeros(ntriplets,1);
        for jj = 1:length(gpcf.metric.components)
          gdist{jj} = zeros(ntriplets,1);
        end
        ntriplets = 0;                
        for ii=1:n-1
          col_ind = ii + find(Cdm(ii+1:n,ii));
          d = zeros(length(col_ind),1);
          d = feval(gpcf.metric.fh.distance, gpcf.metric, x(col_ind,:), x(ii,:));
          
          [gd, gprior_dist] = feval(gpcf.metric.fh.ghyper, gpcf.metric, x(col_ind,:), x(ii,:));

          ntrip_prev = ntriplets;
          ntriplets = ntriplets + length(d);
          
          ind_tr = ntrip_prev+1:ntriplets;
          I(ind_tr) = col_ind;
          J(ind_tr) = ii;
          dist(ind_tr) = d;
          for jj = 1:length(gd)
            gdist{jj}(ind_tr) = gd{jj};
          end
        end
        
        ma2 = gpcf.magnSigma2;
        
        cs = 1-dist;
        
        Dd = -l.*cs.^(l-1);
        Dd = ma2.*Dd;
        
        for i=1:length(gdist)
          ii1 = ii1+1;
          D = Dd.*gdist{i};
          D = sparse(I,J,D,n,n);
          DKff{ii1} = D + D';
        end
      else
        if ~isempty(gpcf.p.lengthScale)
          % loop over all the lengthScales
          if length(gpcf.lengthScale) == 1
            % In the case of isotropic PPCS0
            s2 = 1./gpcf.lengthScale.^2;
            ma2 = gpcf.magnSigma2;
            
            % Calculate the sparse distance (lower triangle) matrix
            d2 = 0;
            for i = 1:m
              d2 = d2 + s2.*(x(I,i) - x(J,i)).^2;
            end
            d = sqrt(d2);
            
            % Create the 'compact support' matrix, that is, (1-R)_+,
            % where ()_+ truncates all non-positive inputs to zero.
            cs = 1-d;
            
            % Calculate the gradient matrix                                        
            D = -l.*cs.^(l-1);
            D = -d.*ma2.*D;
            D = sparse(I,J,D,n,n);
            
            ii1 = ii1+1;
            DKff{ii1} = D;
          else
            % In the case ARD is used
            s2 = 1./gpcf.lengthScale.^2;
            ma2 = gpcf.magnSigma2;
            
            % Calculate the sparse distance (lower triangle) matrix
            % and the distance matrix for each component
            d2 = 0;
            d_l2 = [];
            for i = 1:m
              d_l2(:,i) = s2(i).*(x(I,i) - x(J,i)).^2;
              d2 = d2 + d_l2(:,i);
            end
            d = sqrt(d2);
            d_l = d_l2;
            
            % Create the 'compact support' matrix, that is, (1-R)_+,
            % where ()_+ truncates all non-positive inputs to zero.
            cs = 1-d;
            Dd = -l.*cs.^(l-1);
            Dd = -ma2.*Dd;                    
            int = d ~= 0;
            
            for i = 1:m
              % Calculate the gradient matrix
              D = d_l(:,i).*Dd;
              % Divide by r in cases where r is non-zero
              D(int) = D(int)./d(int);
              D = sparse(I,J,D,n,n);
              
              ii1 = ii1+1;
              DKff{ii1} = D;
            end
          end
        end
      end
      % Evaluate the gradient of non-symmetric covariance (e.g. K_fu)
    elseif nargin == 3
      if size(x,2) ~= size(x2,2)
        error('gpcf_ppcs -> _ghyper: The number of columns in x and x2 has to be the same. ')
      end
      
      ii1=0;
      K = feval(gpcf.fh.cov, gpcf, x, x2);
      if ~isempty(gpcf.p.magnSigma2)
        ii1 = ii1 +1;
        DKff{ii1} = K;
      end

      l = gpcf.l;
      
      if isfield(gpcf,'metric')
        % If other than scaled euclidean metric
        [n1,m1]=size(x);
        [n2,m2]=size(x2);
        
        ma = gpcf.magnSigma2;
        
        % Compute the sparse distance matrix.
        ntriplets = nnz(K);
        I = zeros(ntriplets,1);
        J = zeros(ntriplets,1);
        R = zeros(ntriplets,1);
        dist = zeros(ntriplets,1);
        for jj = 1:length(gpcf.metric.components)
          gdist{jj} = zeros(ntriplets,1);
        end
        ntriplets = 0;
        for ii=1:n2
          d = zeros(n1,1);
          d = feval(gpcf.metric.fh.distance, gpcf.metric, x, x2(ii,:));
          [gd, gprior_dist] = feval(gpcf.metric.fh.ghyper, gpcf.metric, x, x2(ii,:));
          
          I0t = find(d==0);
          d(d >= 1) = 0;
          [I2,J2,R2] = find(d);
          len = length(R);
          ntrip_prev = ntriplets;
          ntriplets = ntriplets + length(R2);

          ind_tr = ntrip_prev+1:ntriplets;
          I(ind_tr) = I2;
          J(ind_tr) = ii;
          dist(ind_tr) = R2;
          for jj = 1:length(gd)
            gdist{jj}(ind_tr) = gd{jj}(I2);
          end
        end

        
        ma2 = gpcf.magnSigma2;
        
        cs = 1-dist;
        
        Dd = -l.*cs.^(l-1);
        Dd = ma2.*Dd;
        
        for i=1:length(gdist)
          ii1 = ii1+1;
          D = Dd.*gdist{i};
          D = sparse(I,J,D,n1,n2);
          DKff{ii1} = D;
        end

      else
        if ~isempty(gpcf.p.lengthScale)
          % loop over all the lengthScales
          if length(gpcf.lengthScale) == 1
            % In the case of isotropic PPCS0
            s2 = 1./gpcf.lengthScale.^2;
            ma2 = gpcf.magnSigma2;
            
            % Calculate the sparse distance (lower triangle) matrix
            dist1 = 0;
            for i=1:m
              dist1 = dist1 + s2.*(bsxfun(@minus,x(:,i),x2(:,i)')).^2;
            end
            d1 = sqrt(dist1); 
            cs1 = max(1-d1,0);
            
            DK_l = -l.*cs1.^(l-1);
            DK_l = -d1.*ma2.*DK_l;
            
            ii1=ii1+1;
            DKff{ii1} = DK_l;
          else
            % In the case ARD is used
            s2 = 1./gpcf.lengthScale.^2;
            ma2 = gpcf.magnSigma2;
            
            % Calculate the sparse distance (lower triangle) matrix
            % and the distance matrix for each component
            dist1 = 0; 
            d_l1 = [];
            for i = 1:m
              dist1 = dist1 + s2(i).*bsxfun(@minus,x(:,i),x2(:,i)').^2;
              d_l1{i} = s2(i).*(bsxfun(@minus,x(:,i),x2(:,i)')).^2;
            end
            d1 = sqrt(dist1); 
            cs1 = max(1-d1,0);
            
            for i = 1:m
              % Calculate the gradient matrix
              DK_l = -l.*cs1.^(l-1);                
              DK_l = -ma2.*DK_l.*d_l1{i};
              % Divide by r in cases where r is non-zero
              DK_l(d1 ~= 0) = DK_l(d1 ~= 0)./d1(d1 ~= 0);
              ii1=ii1+1;
              DKff{ii1} = DK_l;
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
  
  function DKff  = gpcf_ppcs0_ginput(gpcf, x, x2)
  %GPCF_PPCS0_GINPUT  Evaluate gradient of covariance function with 
  %                   respect to x.
  %
  %  Description
  %    DKff = GPCF_PPCS0_GHYPER(GPCF, X) takes a covariance
  %    function data structure GPCF, a matrix X of input vectors
  %    and returns DKff, the gradients of covariance matrix Kff =
  %    k(X,X) with respect to X (cell array with matrix elements)
  %
  %    DKff = GPCF_PPCS0_GHYPER(GPCF, X, X2) takes a covariance
  %    function data structure GPCF, a matrix X of input vectors
  %    and returns DKff, the gradients of covariance matrix Kff =
  %    k(X,X2) with respect to X (cell array with matrix elements).
  %
  %  See also
  %    GPCF_PPCS0_PAK, GPCF_PPCS0_UNPAK, GPCF_PPCS0_E, GP_G

    [n, m] =size(x);
    ii1 = 0;
    if nargin == 2        
      l = gpcf.l;
      K = feval(gpcf.fh.trcov, gpcf, x);
      [I,J] = find(K);
      
      if isfield(gpcf,'metric')
        % Compute the sparse distance matrix and its gradient.
        ntriplets = (nnz(Cdm)-n)./2;
        I = zeros(ntriplets,1);
        J = zeros(ntriplets,1);
        dist = zeros(ntriplets,1);
        for jj = 1:length(gpcf.metric.components)
          gdist{jj} = zeros(ntriplets,1);
        end
        ntriplets = 0;                
        for ii=1:n-1
          col_ind = ii + find(Cdm(ii+1:n,ii));
          d = zeros(length(col_ind),1);
          d = feval(gpcf.metric.fh.distance, gpcf.metric, x(col_ind,:), x(ii,:));
          
          [gd, gprior_dist] = feval(gpcf.metric.fh.ginput, gpcf.metric, x(col_ind,:), x(ii,:));

          ntrip_prev = ntriplets;
          ntriplets = ntriplets + length(d);
          
          ind_tr = ntrip_prev+1:ntriplets;
          I(ind_tr) = col_ind;
          J(ind_tr) = ii;
          dist(ind_tr) = d;
          for jj = 1:length(gd)
            gdist{jj}(ind_tr) = gd{jj};
          end
        end
        
        ma2 = gpcf.magnSigma2;
        
        cs = 1-dist;
        
        Dd = -l.*cs.^(l-1);
        Dd = ma2.*Dd;
        
        for i=1:length(gdist)
          ii1 = ii1+1;
          D = Dd.*gdist{i};
          D = sparse(I,J,D,n,n);
          DKff{ii1} = D + D';
        end
        
      else
        if length(gpcf.lengthScale) == 1
          % In the case of an isotropic PPCS0
          s2 = repmat(1./gpcf.lengthScale.^2, 1, m);
        else
          s2 = 1./gpcf.lengthScale.^2;
        end
        ma2 = gpcf.magnSigma2;
        
        % Calculate the sparse distance (lower triangle) matrix
        % and the distance matrix for each component
        d2 = 0;
        for i = 1:m
          d2 = d2 + s2(i).*(x(I,i) - x(J,i)).^2;
        end
        d = sqrt(d2);
        
        % Create the 'compact support' matrix, that is, (1-R)_+,
        % where ()_+ truncates all non-positive inputs to zero.
        cs = 1-d;
        
        Dd = -ma2.*l.*cs.^(l-1);
        Dd = sparse(I,J,Dd,n,n);
        d = sparse(I,J,d,n,n);
        
        row = ones(n,1);
        cols = 1:n;
        for i = 1:m
          for j = 1:n
            % Calculate the gradient matrix
            ind = find(d(:,j));
            apu = full(Dd(:,j)).*s2(i).*(x(j,i)-x(:,i));
            apu(ind) = apu(ind)./d(ind,j);
            D = sparse(row*j, cols, apu, n, n);
            D = D+D';
            
            ii1 = ii1+1;
            DKff{ii1} = D;
          end
        end
      end

      % Evaluate the gradient of non-symmetric covariance (e.g. K_fu)
    elseif nargin == 3
      if size(x,2) ~= size(x2,2)
        error('gpcf_ppcs -> _ghyper: The number of columns in x and x2 has to be the same. ')
      end
      
      K = feval(gpcf.fh.cov, gpcf, x, x2);
      n2 = size(x2,1);
      
      ii1=0;
      l = gpcf.l;
      
      if isfield(gpcf,'metric')
        % If other than scaled euclidean metric
        [n1,m1]=size(x);
        [n2,m2]=size(x2);
        
        ma = gpcf.magnSigma2;
        
        % Compute the sparse distance matrix.
        ntriplets = nnz(K);
        I = zeros(ntriplets,1);
        J = zeros(ntriplets,1);
        R = zeros(ntriplets,1);
        dist = zeros(ntriplets,1);
        for jj = 1:length(gpcf.metric.components)
          gdist{jj} = zeros(ntriplets,1);
        end
        ntriplets = 0;
        for ii=1:n2
          d = zeros(n1,1);
          d = feval(gpcf.metric.fh.distance, gpcf.metric, x, x2(ii,:));
          [gd, gprior_dist] = feval(gpcf.metric.fh.ginput, gpcf.metric, x, x2(ii,:));
          
          I0t = find(d==0);
          d(d >= 1) = 0;
          [I2,J2,R2] = find(d);
          len = length(R);
          ntrip_prev = ntriplets;
          ntriplets = ntriplets + length(R2);

          ind_tr = ntrip_prev+1:ntriplets;
          I(ind_tr) = I2;
          J(ind_tr) = ii;
          dist(ind_tr) = R2;
          for jj = 1:length(gd)
            gdist{jj}(ind_tr) = gd{jj}(I2);
          end
        end

        
        ma2 = gpcf.magnSigma2;
        
        cs = 1-dist;
        
        Dd = -l.*ma2.*cs.^(l-1);
        
        for i=1:length(gdist)
          ii1 = ii1+1;
          D = Dd.*gdist{i};
          D = sparse(I,J,D,n1,n2);
          DKff{ii1} = D;
        end

      else
        if length(gpcf.lengthScale) == 1
          % In the case of an isotropic PPCS0
          s2 = repmat(1./gpcf.lengthScale.^2, 1, m);
        else
          s2 = 1./gpcf.lengthScale.^2;
        end
        ma2 = gpcf.magnSigma2;
        
        % Calculate the sparse distance (lower triangle) matrix
        % and the distance matrix for each component
        dist1 = 0;
        for i = 1:m
          dist1 = dist1 + s2(i).*bsxfun(@minus,x(:,i),x2(:,i)').^2;
        end
        d = sqrt(dist1); 
        cs = max(1-d,0);
        Dd = -ma2.*l.*cs.^(l-1);
        
        row = ones(n2,1);
        cols = 1:n2;
        for i = 1:m
          for j = 1:n
            % Calculate the gradient matrix
            ind = find(d(j,:));
            apu = Dd(j,:).*s2(i).*(x(j,i)-x2(:,i))';
            apu(ind) = apu(ind)./d(j,ind);
            D = sparse(row*j, cols, apu, n, n2);
            
            ii1 = ii1+1;
            DKff{ii1} = D;
          end
        end
      end
    end
  end
  
  
  function C = gpcf_ppcs0_cov(gpcf, x1, x2, varargin)
  %GP_PPCS0_COV  Evaluate covariance matrix between two input vectors.
  %
  %  Description         
  %    C = GP_PPCS0_COV(GP, TX, X) takes in covariance function of
  %    a Gaussian process GP and two matrixes TX and X that contain
  %    input vectors to GP. Returns covariance matrix C. Every
  %    element ij of C contains covariance between inputs i in TX
  %    and j in X.
  %
  %  See also
  %    GPCF_PPCS0_TRCOV, GPCF_PPCS0_TRVAR, GP_COV, GP_TRCOV

    if isfield(gpcf,'metric')
      % If other than scaled euclidean metric
      [n1,m1]=size(x1);
      [n2,m2]=size(x2);
      
      ma2 = gpcf.magnSigma2;
      l = gpcf.l;
      
      % Compute the sparse distance matrix.
      ntriplets = max(1,floor(0.03*n1*n2));
      I = zeros(ntriplets,1);
      J = zeros(ntriplets,1);
      R = zeros(ntriplets,1);
      ntriplets = 0;
      I0=zeros(ntriplets,1);
      J0=zeros(ntriplets,1);
      nn0=0;
      for ii1=1:n2
        d = zeros(n1,1);
        d = feval(gpcf.metric.fh.distance, gpcf.metric, x1, x2(ii1,:));
        I0t = find(d==0);
        d(d >= 1) = 0;
        [I2,J2,R2] = find(d);
        len = length(R);
        ntrip_prev = ntriplets;
        ntriplets = ntriplets + length(R2);

        I(ntrip_prev+1:ntriplets) = I2;
        J(ntrip_prev+1:ntriplets) = ii1;
        R(ntrip_prev+1:ntriplets) = R2;
        I0(nn0+1:nn0+length(I0t)) = I0t;
        J0(nn0+1:nn0+length(I0t)) = ii1;
        nn0 = nn0+length(I0t);
      end
      r = sparse(I(1:ntriplets),J(1:ntriplets),R(1:ntriplets));
      [I,J,r] = find(r);
      cs = full(sparse(max(0, 1-r)));
      C = ma2.*cs.^l;
      C = sparse(I,J,C,n1,n2) + sparse(I0,J0,ma2,n1,n2);
    else
      % If scaled euclidean metric
      
      [n1,m1]=size(x1);
      [n2,m2]=size(x2);
      
      s = 1./(gpcf.lengthScale);
      s2 = s.^2;
      if size(s)==1
        s2 = repmat(s2,1,m1);
      end
      ma2 = gpcf.magnSigma2;
      l = gpcf.l;
      
      % Compute the sparse distance matrix.
      ntriplets = max(1,floor(0.03*n1*n2));
      I = zeros(ntriplets,1);
      J = zeros(ntriplets,1);
      R = zeros(ntriplets,1);
      ntriplets = 0;
      I0=zeros(ntriplets,1);
      J0=zeros(ntriplets,1);
      nn0=0;
      for ii1=1:n2
        d = zeros(n1,1);
        for j=1:m1
          d = d + s2(j).*(x1(:,j)-x2(ii1,j)).^2;
        end
        d = sqrt(d);
        I0t = find(d==0);
        d(d >= 1) = 0;
        [I2,J2,R2] = find(d);
        len = length(R);
        ntrip_prev = ntriplets;
        ntriplets = ntriplets + length(R2);

        I(ntrip_prev+1:ntriplets) = I2;
        J(ntrip_prev+1:ntriplets) = ii1;
        R(ntrip_prev+1:ntriplets) = R2;
        I0(nn0+1:nn0+length(I0t)) = I0t;
        J0(nn0+1:nn0+length(I0t)) = ii1;
        nn0 = nn0+length(I0t);
      end
      r = sparse(I(1:ntriplets),J(1:ntriplets),R(1:ntriplets));
      [I,J,r] = find(r);
      cs = full(sparse(max(0, 1-r)));
      
      C = ma2.*cs.^l;
      C = sparse(I,J,C,n1,n2) + sparse(I0,J0,ma2,n1,n2);
    end
  end

  function C = gpcf_ppcs0_trcov(gpcf, x)
  %GP_PPCS0_TRCOV  Evaluate training covariance matrix of inputs.
  %
  %  Description
  %    C = GP_PPCS0_TRCOV(GP, TX) takes in covariance function of a
  %    Gaussian process GP and matrix TX that contains training
  %    input vectors. Returns covariance matrix C. Every element ij
  %    of C contains covariance between inputs i and j in TX
  %
  %  See also
  %    GPCF_PPCS0_COV, GPCF_PPCS0_TRVAR, GP_COV, GP_TRCOV

    if isfield(gpcf,'metric')
      % If other than scaled euclidean metric
      [n, m] =size(x);            
      ma2 = gpcf.magnSigma2;
      l = gpcf.l;
      
      % Compute the sparse distance matrix.
      ntriplets = max(1,floor(0.03*n*n));
      I = zeros(ntriplets,1);
      J = zeros(ntriplets,1);
      R = zeros(ntriplets,1);
      ntriplets = 0;
      for ii1=1:n-1
        d = zeros(n-ii1,1);
        col_ind = ii1+1:n;
        d = feval(gpcf.metric.fh.distance, gpcf.metric, x(col_ind,:), x(ii1,:));
        d(d >= 1) = 0;
        [I2,J2,R2] = find(d);
        len = length(R);
        ntrip_prev = ntriplets;
        ntriplets = ntriplets + length(R2);
        if (ntriplets > len)
          I(2*len) = 0;
          J(2*len) = 0;
          R(2*len) = 0;
        end
        ind_tr = ntrip_prev+1:ntriplets;
        I(ind_tr) = ii1+I2;
        J(ind_tr) = ii1;
        R(ind_tr) = R2;
      end
      R = sparse(I(1:ntriplets),J(1:ntriplets),R(1:ntriplets),n,n);
      
      % Find the non-zero elements of R.
      [I,J,rn] = find(R);
      cs = max(0,1-rn);
      C = ma2.*cs.^l;
      C = sparse(I,J,C,n,n);
      C = C + C' + sparse(1:n,1:n,ma2,n,n);
      
    else
      % If a scaled euclidean metric try first mex-implementation 
      % and if there is not such... 
      C = trcov(gpcf,x);
      % ... evaluate the covariance here.
      if isnan(C)
        [n, m] =size(x);
        
        s = 1./(gpcf.lengthScale);
        s2 = s.^2;
        if size(s)==1
          s2 = repmat(s2,1,m);
        end
        ma2 = gpcf.magnSigma2;
        l = gpcf.l;
        
        % Compute the sparse distance matrix.
        ntriplets = max(1,floor(0.03*n*n));
        I = zeros(ntriplets,1);
        J = zeros(ntriplets,1);
        R = zeros(ntriplets,1);
        ntriplets = 0;
        for ii1=1:n-1
          d = zeros(n-ii1,1);
          col_ind = ii1+1:n;
          for ii2=1:m
            d = d+s2(ii2).*(x(col_ind,ii2)-x(ii1,ii2)).^2;
          end
          %d = sqrt(d);
          d(d >= 1) = 0;
          [I2,J2,R2] = find(d);
          len = length(R);
          ntrip_prev = ntriplets;
          ntriplets = ntriplets + length(R2);
          if (ntriplets > len)
            I(2*len) = 0;
            J(2*len) = 0;
            R(2*len) = 0;
          end
          ind_tr = ntrip_prev+1:ntriplets;
          I(ind_tr) = ii1+I2;
          J(ind_tr) = ii1;
          R(ind_tr) = sqrt(R2);
        end
        R = sparse(I(1:ntriplets),J(1:ntriplets),R(1:ntriplets),n,n);
        
        % Find the non-zero elements of R.
        [I,J,rn] = find(R);
        cs = max(0,1-rn);
        C = ma2.*cs.^l;
        C = sparse(I,J,C,n,n);
        C = C + C' + sparse(1:n,1:n,ma2,n,n);
      end
    end
  end

  function C = gpcf_ppcs0_trvar(gpcf, x)
  %GP_PPCS0_TRVAR  Evaluate training variance vector
  %
  %  Description
  %    C = GP_PPCS0_TRVAR(GPCF, TX) takes in covariance function of
  %    a Gaussian process GPCF and matrix TX that contains training
  %    inputs. Returns variance vector C. Every element i of C
  %    contains variance of input i in TX
  %
  %  See also
  %    GPCF_PPCS0_COV, GP_COV, GP_TRCOV

    [n, m] =size(x);

    C = ones(n,1).*gpcf.magnSigma2;
    C(C<eps)=0;
  end

  function reccf = gpcf_ppcs0_recappend(reccf, ri, gpcf)
  %RECAPPEND  Record append
  %
  %  Description
  %    RECCF = GPCF_PPCS0_RECAPPEND(RECCF, RI, GPCF)
  %    takes a covariance function record structure RECCF, record
  %    index RI and covariance function structure GPCF with the
  %    current MCMC samples of the hyperparameters. Returns
  %    RECCF which contains all the old samples and the
  %    current samples from GPCF .
  %
  %  See also
  %    GP_MC and GP_MC -> RECAPPEND

  % Initialize record
    if nargin == 2
      reccf.type = 'gpcf_ppcs0';
      reccf.nin = ri.nin;
      reccf.l = floor(reccf.nin/2)+4;

      % cf is compactly supported
      reccf.cs = 1;
      
      % Initialize parameters
      reccf.lengthScale= [];
      reccf.magnSigma2 = [];

      % Set the function handles
      reccf.fh.pak = @gpcf_ppcs0_pak;
      reccf.fh.unpak = @gpcf_ppcs0_unpak;
      reccf.fh.e = @gpcf_ppcs0_e;
      reccf.fh.g = @gpcf_ppcs0_g;
      reccf.fh.cov = @gpcf_ppcs0_cov;
      reccf.fh.trcov  = @gpcf_ppcs0_trcov;
      reccf.fh.trvar  = @gpcf_ppcs0_trvar;
      reccf.fh.recappend = @gpcf_ppcs0_recappend;  
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

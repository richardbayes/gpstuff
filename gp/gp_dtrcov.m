function [K, C] = gp_dtrcov(gp, x1, x2,predcf)
%GP_TRCOV  Evaluate training covariance matrix (gp_cov + noise covariance).
%
%  Description
%    K = GP_TRCOV(GP, TX, PREDCF) takes in Gaussian process GP and
%    matrix TX that contains training input vectors to GP. Returns
%    (noiseless) covariance matrix K for latent values, which is
%    formed as a sum of the covariance matrices from covariance
%    functions in gp.cf array. Every element ij of K contains
%    covariance between inputs i and j in TX. PREDCF is an array
%    specifying the indexes of covariance functions, which are used
%    for forming the matrix. If not given, the matrix is formed
%    with all functions.
%
%    [K, C] = GP_TRCOV(GP, TX, PREDCF) returns also the (noisy)
%    covariance matrix C for observations y, which is sum of K and
%    diagonal term, for example, from Gaussian noise.
%
%  See also
%    GP_SET, GPCF_*

% Copyright (c) 2006-2010 Jarno Vanhatalo
% Copyright (c) 2010 Tuomas Nikoskinen

% This software is distributed under the GNU General Public
% License (version 3 or later); please refer to the file
% License.txt, included with the software, for details.
if (isfield(gp,'derivobs') && gp.derivobs)
  ncf=length(gp.cf);
  K=zeros(length(x1)+size(x2,2).*length(x2));
  % Loop over covariance functions
  for i=1:ncf
    % Derivative observations
    gpcf = gp.cf{i};            % only for sexp at the moment
    [n,m]=size(x2);
    if m==1
      Kff = gpcf.fh.trcov(gpcf, x1);
      Gset = gpcf.fh.ginput4(gpcf, x2,x1);
      D = gpcf.fh.ginput2(gpcf, x2, x2);
      Kdf=Gset{1};
      Kfd = Kdf;
      Kdd=D{1};
      
      % Add all the matrices into a one K matrix
      K = K+[Kff Kfd'; Kfd Kdd];
      [a b] = size(K);
      
      % MULTIDIMENSIONAL input dim >1
    else
      Kff = gpcf.fh.trcov(gpcf, x1);
      if ~isequal(x2,x1)
        G = gpcf.fh.ginput4(gpcf, x2,x1);
      else
        G = gpcf.fh.ginput4(gpcf, x2);
      end
      D= gpcf.fh.ginput2(gpcf, x2, x2);
      Kdf2 = gpcf.fh.ginput3(gpcf, x2 ,x2);
      
      Kfd=cat(1,G{:});
%       Kfd=[G{1:m}];
      
      % Now build up Kdd m*n x m*n matrix, which contains all the
      % both partial derivative" -matrices
      Kdd=blkdiag(D{1:m});
      
      % Gather non-diagonal matrices to Kddnodi
      if m==2
        Kddnodi=[zeros(n,n) Kdf2{1};Kdf2{1} zeros(n,n)];
      else
        t1=1;
        Kddnodi=zeros(m*n,m*n);
        for i=1:m-1
          aa=zeros(m-1,m);
          t2=t1+m-2-(i-1);
          aa(m-1,i)=1;
          k=kron(aa,cat(1,zeros((i)*n,n),Kdf2{t1:t2}));
          k(1:n*m,:)=[];
          k=k+k';
          Kddnodi = Kddnodi + k;
          t1=t2+1;
        end
      end
      % Sum the diag + no diag matrices
      Kdd=Kdd+Kddnodi;
      
      % Gather all the matrices into one final matrix K which is the
      % training covariance matrix
      K = K+[Kff Kfd'; Kfd Kdd];
      [a b] = size(K);
    end    
  end  
  %add jitterSigma2 to the diagonal
  if ~isempty(gp.jitterSigma2)
    a1=a + 1;
    K(1:a1:end)=K(1:a1:end) + gp.jitterSigma2;
  end
  if nargout > 1
    C = K;
    if isfield(gp,'lik2') && isequal(gp.lik2.type, 'Gaussian');
      % Add Gaussian noise to the covariance
      % same noise for obs and grad obs
      lik2 = gp.lik2;
      Noi=lik2.fh.trcov(lik2, x1);
      x2=repmat(x1,m,1);
      Cff = Kff + Noi;
      C = [Cff Kfd'; Kfd Kdd];
    end
  end
end

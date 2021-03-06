% FUNCTION FEMIC_inverse2D.m
%
% This function conmputes the weighted nonlinear least-squares inverse via a
% modified Levenberg-Marquardt scheme with regularized smoothing
% constraints.  Added regularization for smoothing are selected by user to
% produce 2D electrical conducttivity models from frequency-domain EM data.
% The 2D regularization constraint formulation is similar to the that
% developed by Constable et al. for inversion of magnetotellurics data.
%
% The inverse model iteratively call the forward model function
% FEMIC_Jacobian.m until the convergence criteria are met.  The modified LM
% objective function ||d-G(m)||p + muh(R) + muv(R) + (gamma/2)(X) are
% linearized using Taylor-series expansion and lead to:
% A= muv(deltaV'*deltaV)+muh(deltaH'*deltaH)+(gamma/2)*X*'X+(W*J)'*(W*J)
% b=(W*J')*W*(d-G+J*dp)+(gamma/2)*(X'*X)
% where p_trial = A\b (by Cholesky factorization, Discrepancy, or Max Entropy)
%
% See Refrence: Schultz and Ruppel, 2005, Geophysics
% Also see FEMIC code technical note and manual, 2008
% 
% Originated by: Greg Schultz
% Modified from original codes produced in 2004/2008
% Significantly modifield in 2008 to incorporate the log-barrier function
% constraint to enforce positivity and add a number of other features
% Code delivered to the USGS-Storrs in June 2008
%
%%
% INPUTS:
% priori = user defined priori information 
% sx=smoothness in the x-direction
%sz= smoothness in the z-direction
%   params = model parameters to be optimizaed
%   d = depths (initial) (1 x mlayers)
%   pobs = measurements (expected to be VDM cat HDM both (1 x 2*length(f))
%   sigma = standard deviations on measurements (1 x 2*length(f))
%   f = frequencies
%   r = separation distances between Rx and Tx for bistatic case
%   muh = horizontal regularization coeffecient
%   muv = vertical regularization coeffectient
%   tol_eca = tolerance on changes to conductivity
%   err_tol = convergence criteria for changing errors
%   max_iter = maximum no. of allowable iterations
%   q = [=1,2,3] to designate the data types represented in the pobs input
%       array: 1=Vertical Magnetic Dipole only
%              2=Horizontal Magnetic Dipole only
%              3=Both VMD and HMD data
%// Inputs are generally specificied by the Matlab GUI code FEMIC_InvGUI.m
%%
% OUTPUTS:
%   p_final = the final model array in [P stations x N frequencies (2xN for
%       both VMD and HMD data)] form
%   muh_final = the final horizontal regulatization coeffecient
%   rms_error = the history of the Lp norm rms errors between forward model
%       results (G(m)) and data (d)
%
% EXAMPLE USAGE:
% [p,mu,errRMS,g]=FEMIC_inverse2D(params,d,pobs,sigma,f,r,muh,muv,tol_eca,err_tol,max_iter,q);

function [p_final, mu_final, rms_error, G, x, zz]=FEMIC_inverse2D(initmodel_cond, init_lyrthick,pobs,sigma,coords,f,r,muh,muv,...
    tol_eca,err_tol,max_iter,q,pmin,pmax,barrier,invType,priori,sx,sz, statusUpdate,sens,vall,plotdoi,perc,el,cell_sens)
LCURVEf = 0;                % Initialize LCURVE method to DEFAULT (=not used)
warning ('off');

parpool('local',vall)

boo=init_lyrthick;
sigma=sigma(:);

if LCURVEf, 
    muv=muv;
else
    muv=muv;
end
for i=1:length(initmodel_cond)
    aaaa(i)=length(initmodel_cond{i});
    boo{i}=zeros(length(boo{i}),1);
end
for i=1:length(initmodel_cond)
    
    if length(initmodel_cond{i})<max(aaaa);
        dd=initmodel_cond{i};
        da=init_lyrthick{i};
        fa=boo{i};
        dd(length(initmodel_cond{i}):max(aaaa))=dd(length(initmodel_cond{i}))*(ones(length(length(initmodel_cond{i}):max(aaaa)),1));
        da(length(init_lyrthick{i}):max(aaaa))=da(length(init_lyrthick{i}))*(ones(length(length(init_lyrthick{i}):max(aaaa)),1));
        fa(length(boo{i}):max(aaaa))=zeros(length(length(boo{i}):max(aaaa)),1);
    else
       dd=initmodel_cond{i};
       da=init_lyrthick{i};
       fa=boo{i};
    end
    params(:,i)=dd;
    d(:,i)=da;
    wta(:,i)=fa;
end

porder = 2;             % norm order (p-value) for error calc (p=2 -> L2 norm)
P=size(pobs,2);         % number of frequencies (x2) by number of stations
PP=size(pobs,1);               % number of data (freq x 2)
%M=length(d);     
M = size(params,1);     % number of model parameters
Md = size(d,1);         % number of layer thicknesses
Ms = M-Md;              % should be the number of conducitivities
%N=szp(1);
N=length(f);            % number of frequencies
if q==3,
    NN=2*N;             % twice the frequenices if both VDM and HDM used
else
    NN=N;               % total number of data points (same as N if only one orientation of data is used)
end
NP=NN*P;                % size of the data set
MP=M*P;                 % size of the model output set
wta=zeros(Md,P);

% import the user defined priori information in the starting model
[faa fo]=size(priori);
% Create a NPxNP diagonal weighting matrix whose elements are the inverse of the
% estimated (or measured) standard deviations of the measurements
        for lo=1:faa
        ll=priori(lo,1);
        qq=priori(lo,2);
        params(qq,ll)=priori(lo,3);
        wta(qq,ll)=priori(lo,4);
        end
        po=params(1:M,:);
        obs=(reshape(pobs,NP,1));
        MM.k=length(po(:,1));
        dx=ones(P,1);dz=d(:,1);nx=length(dx);nz=length(dz);
        [Gx Gz]=grad(dx,dz);
        Gs = [sx*Gx;sz*Gz];
        wta=1-wta;
        Wt = spdiags(wta(:),0,nx*nz,nx*nz);
        MW = Wt' * ( Gs' * Gs) * Wt;
       %sigma=repmat(sigma, P, 1);
      

W=diag(1./sigma);
dp=1;
tic;
%MM.con=po;
%MM.thk=d;
MM.chie=zeros(MM.k,1);
MM.chim=zeros(MM.k,1);
S.freq=f;
for i=1:length(f);S.tor{i}='z';end;S.tor=reshape(S.tor,length(f),1);
S.tmom=ones(length(f),1);
S.tx=zeros(length(f),1);
S.ty=zeros(length(f),1);
S.tzoff=zeros(length(f),1);
S.ror=S.tor;
S.rmom=ones(length(f),1);
S.rx=1.66*ones(length(f),1);
S.ry=zeros(length(f),1);
S.rzoff=zeros(length(f),1);
S.nf=length(f);
S.r=S.rx;
%el=-1;


switch invType
    case(1),
        inversionTypechar = 'Occams Inversion (Fixed Reg. Coeff.)';
%    case(2),
 %       inversionTypechar = 'Truncated SVD (Discrepancy Principle)';
  %  case(3)
   %     inversionTypechar = 'Maximum Entropy';
 %   case(4),
  %      inversionTypechar = 'Occams Inversion (L-curve)';
   % case (5)
    %     inversionTypechar = 'Biconjugate gradient stabilizing method';
  %  case (6)
   %      inversionTypechar = 'Thiknov inversion';
    otherwise
        inversionTypechar = 'Unkwown Inversion Method!!!';
end
fprintf('******  STARTING FEMIC INVERSION  ******\n');
str='******  STARTING FEMIC INVERSION  ******';
statusUpdate(str);

fprintf(['  Inversion Type: ',inversionTypechar]);
fprintf('\n');
str=strcat('Inversion Type: ', inversionTypechar);
statusUpdate(str)

fprintf('  Maximum Iterations: %i; Error Tolerance: %f; Model Change Tolerance: %f\n',max_iter,err_tol,tol_eca);
str=strcat('Maximum Iterations: ', num2str(max_iter), ' Error tolerance: ', num2str(err_tol), ' Model Change tolerance: ', num2str(tol_eca));
statusUpdate(str);

first=true;
switch invType
             case (1)           
               muv=max(muv);MM.con=params;MM.thk=init_lyrthick{1};
               [p_final, muh_final, rms_error, G,sense,cell_sensy]=FEMIC_tost2(MM,S,el,pobs,sigma,muv,err_tol,max_iter,q,sx,sz,wta,pmin,pmax,coords,sens,cell_sens);
               mu_final=muv(1);rms_error=min(rms_error);
               ccc=zeros(max(aaaa),length(init_lyrthick));
       for cnt=1:length(init_lyrthick)
           if length(init_lyrthick{cnt})>=max(aaaa)
             bbb=init_lyrthick{cnt};
             ccc(:,cnt)=bbb;
           end
       end
       [m n]=size(ccc);
       ccc(m,:)=ccc(m-1,:);
       ea=cumsum(ccc);zz=max(ea')';
       x=coords(:,2);
       [X,Y]=meshgrid(x,zz);
       rt = max([max(sense) abs(min(sense))]);
                   sense = sense/rt;
                   sense=reshape(sense,M,P);sense=abs(sense);
                   figure;[me]=contourf(x,zz,abs(sense)); 
                   mee = getcontourlines(me);close;  

               if sens && plotdoi && cell_sens
                   [doi]=FEMIC_DOII(MM,S,el,pobs,sigma,f,r,muv,err_tol,max_iter,q,vall,perc,sx,sz,wta,init_lyrthick,pmin,pmax,coords);
                   figure;
                   rt = max([max(sense) abs(min(sense))]);
                   sense = sense/rt;
       subplot(5,1,1);imagesc(x,zz,pobs);title('Measured Data'); xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Conductivity [mS/m]')
       subplot(5,1,2);imagesc(x,zz,reshape(G,PP,P));title('Estimated data');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Conductivity [mS/m]')
       subplot(5,1,3);contourf(x,zz,reshape(p_final,M,P));
        a0=[mee.v];
                for i=1:P;
                    aa0=find(sense(:,i)<a0(2));
                    if isempty(aa0)
                        aa0=find(sense(:,i)==min(sense(:,i)));
                    end
                        aa2(i)=aa0(1);
                end
                     
               hold on;plot(x,-zz(aa2),'-p','LineWidth',2,...
                'MarkerEdgeColor','r',...
                'MarkerFaceColor','g',...
                'MarkerSize',5); title('Inverted Model');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Conductivity [mS/m]');hold off
       subplot(5,1,4);imagesc(x,zz,reshape(abs(sense),M,P));title('Model resolution');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Resolution')
       subplot(5,1,5);imagesc(x,zz,reshape(abs(cell_sensy),M,P));title('Model mesh sensitivity');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Sensitivity')
       
       elseif sens && plotdoi 
                   [doi]=FEMIC_DOII(MM,S,el,pobs,sigma,f,r,muv,err_tol,max_iter,q,vall,perc,sx,sz,wta,init_lyrthick,pmin,pmax,coords);
                   
                  
                   figure;
       subplot(4,1,1);imagesc(x,zz,pobs);title('Measured Data'); xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Conductivity [mS/m]')
       subplot(4,1,2);imagesc(x,zz,reshape(G,PP,P));title('Estimated data');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Conductivity [mS/m]')
       subplot(4,1,3);contourf(x,-zz,reshape(10.^p_final,M,P),20,'LineColor','none');%hold on;plot(x,doi,'--k','LineWidth',2,...
                  a0=[mee.v];
                for i=1:P;
                    aa0=find(sense(:,i)<a0(2));
                    if isempty(aa0)
                        aa0=find(sense(:,i)==min(sense(:,i)));
                    end
                        aa2(i)=aa0(1);
                end
                     
               hold on;plot(x,-zz(aa2),'-p','LineWidth',2,...
                'MarkerEdgeColor','r',...
                'MarkerFaceColor','g',...
                'MarkerSize',5); title('Inverted Model');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Conductivity [mS/m]');hold off
       subplot(4,1,4);imagesc(x,zz,reshape(abs(sense),M,P));title('Model resolution');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Resolution')
       
       elseif sens && cell_sens 
                   [doi]=FEMIC_DOII(MM,S,el,pobs,sigma,f,r,muv,err_tol,max_iter,q,vall,perc,sx,sz,wta,init_lyrthick,pmin,pmax,coords);
                   figure;
                   rt = max([max(sense) abs(min(sense))]);
                   sense = sense/rt;
       subplot(5,1,1);imagesc(x,zz,pobs);title('Measured Data'); xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Conductivity [mS/m]')
       subplot(5,1,2);imagesc(x,zz,reshape(G,PP,P));title('Estimated data');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Conductivity [mS/m]')
       subplot(5,1,3);imagesc(x,zz,reshape(p_final,M,P));hold on;plot(x,doi,'--k','LineWidth',2,...
                'MarkerEdgeColor','k',...
                'MarkerFaceColor','g',...
                'MarkerSize',10); title('Inverted Model');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Conductivity [mS/m]')
       subplot(5,1,4);imagesc(x,zz,reshape(abs(sense),M,P));title('Model resolution');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Resolution')
       subplot(5,1,5);imagesc(x,zz,reshape(abs(cell_sensy),M,P));title('Model mesh sensitivity');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Sensitivity')
       
       elseif cell_sens && plotdoi 
                   [doi]=FEMIC_DOII(MM,S,el,pobs,sigma,f,r,muv,err_tol,max_iter,q,vall,perc,sx,sz,wta,init_lyrthick,pmin,pmax,coords);
                   figure;
                   rt = max([max(sense) abs(min(sense))]);
                   sense = sense/rt;
       subplot(4,1,1);imagesc(x,zz,pobs);title('Measured Data'); xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Conductivity [mS/m]')
       subplot(4,1,2);imagesc(x,zz,reshape(G,PP,P));title('Estimated data');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Conductivity [mS/m]')
       subplot(4,1,3);imagesc(x,-zz,reshape(p_final,M,P));
        a0=[mee.v];
                for i=1:P;
                    aa0=find(sense(:,i)<a0(2));
                    if isempty(aa0)
                        aa0=find(sense(:,i)==min(sense(:,i)));
                    end
                        aa2(i)=aa0(1);
                end
                     
               hold on;plot(x,-zz(aa2),'-p','LineWidth',2,...
                'MarkerEdgeColor','r',...
                'MarkerFaceColor','g',...
                'MarkerSize',5); title('Inverted Model');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Conductivity [mS/m]');hold off
       subplot(4,1,4);imagesc(x,zz,reshape(abs(cell_sensy),M,P));title('Model mesh sensitivity');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Sensitivity')
             
       elseif sens
           figure;           
           rt = max([max(sense) abs(min(sense))]);
           sense = sense/rt;

       subplot(4,1,1);imagesc(x,zz,pobs);title('Measured Data');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Quadrature') 
       subplot(4,1,2);imagesc(x,zz,reshape(G,PP,P));title('Estimated data');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Quadrature')
       subplot(4,1,3);imagesc(x,zz,reshape(p_final,M,P));title('Inverted Model');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'log10(Conductivity) [S/m]')
       subplot(4,1,4);imagesc(x,zz,reshape(abs(sense),M,P));title('Model resolution');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Resolution')
       
       elseif cell_sens
           figure;           
       subplot(4,1,1);imagesc(x,zz,pobs);title('Measured Data');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Quadrature') 
       subplot(4,1,2);imagesc(x,zz,reshape(G,PP,P));title('Estimated data');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Quadrature')
       subplot(4,1,3);imagesc(x,zz,reshape(p_final,M,P));title('Inverted Model');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'log10(Conductivity) [S/m]')
       subplot(4,1,4);imagesc(x,zz,reshape(abs(cell_sensy),M,P));title('Model mesh sensitivity');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Sensitivity')
       
       elseif plotdoi
          % [doi]=FEMIC_DOII(MM,S,el,pobs,sigma,f,r,muv,err_tol,max_iter,q,vall,perc,sx,sz,wta,init_lyrthick,pmin,pmax,coords);
           figure;
       subplot(3,1,1);imagesc(x,zz,pobs);title('Measured Data'); xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Quadrature')
       subplot(3,1,2);imagesc(x,zz,reshape(G,PP,P));title('Estimated data');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Quadrature')
       subplot(3,1,3);imagesc(x,-zz,reshape(p_final,M,P));
        a0=[mee.v];
                for i=1:P;
                    aa0=find(sense(:,i)<a0(2));
                    if isempty(aa0)
                        aa0=find(sense(:,i)==min(sense(:,i)));
                    end
                        aa2(i)=aa0(1);
                end
                dlmwrite('doi.dat',-zz(aa2));     
               hold on;plot(x,-zz(aa2),'-rp','LineWidth',2,...
                'MarkerEdgeColor','r',...
                'MarkerFaceColor','g',...
                'MarkerSize',5); title('Inverted Model');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Conductivity [mS/m]');hold off
              
               else
           figure;
       subplot(3,1,1);imagesc(x,zz,pobs);title('Measured Data');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Quadrature')
       subplot(3,1,2);imagesc(x,zz,reshape(G,PP,P));title('Estimated data');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'Quadrature')
       subplot(3,1,3);imagesc(x,zz,reshape(p_final,M,P)); title('Inverted Model');xlabel('Distance[m]');ylabel('Depth [m]');colorbar;title(colorbar,'log10(Conductivity) [S/m]')
               end
       return;

 end
%% Outer loop over maximum number of iterations (breaks if alternate
%  convergence criteria are met)


* Macro to run Kalman filter for trend only without seasonal patterns;
%macro kalfil(tauratio,run);
* Forward sweep of Kalman filter;
proc iml;
   use work.centre var {ratestd yrmon};
   read all;
   use work.sigma var {sigma};
   read all;
   n=nrow(ratestd);
   data={0}//ratestd;
   yyy={0}//yrmon;
   F={1,0};
   tau=sigma/&tauratio.;
   delta=1; G={1 1,0 1}; G[1,2]=delta;
   V=J(2,2,0); V[1,1]=(delta**3)/3; V[1,2]=(delta**2)/2; V[2,1]=(delta**2)/2; V[2,2]=delta;
   V=V*(tau**2);
   a_j=J(2,n+1,0);   p_j=J(2,n+1,0);
   e_j=J(1,n+1,0);   C_j=J(2,2,0);
   p_j[1,1]=data[+,1]/n; *<first obs=mean (p_0);
   C_j[1,1]=100; C_j[2,2]=100; * <- relaxed priors (C_0);
   Q_j=J(2,2,0); R_j=J(2,2,0);
   C_out=J((n+1)*4,1,0); R_out=J((n+1)*4,1,0);
   C_out[1,]=C_j[1,1];
   C_out[4,]=C_j[2,2];
   time=(0:n)`;
   do t=1 to n; *<- time 0 to n-1;
	  a_j[,t+1]=G*p_j[,t];
	  R_j=(G*C_j*G`)+V;
	  Q_j=(F`*R_j*F)+sigma;
      e_j[,t+1]=data[t+1,1]-(F`*a_j[,t+1]);
      p_j[,t+1]=a_j[,t+1]+(R_j*F*inv(Q_j)*e_j[,t+1]);
      C_j=R_j-(R_j*F*inv(Q_j)*F`*R_j`);
      C_out[(t*4)+1:((t+1)*4),]=shape(C_j,4,1);
      R_out[(t*4)+1:((t+1)*4),]=shape(R_j,4,1);
   end;
* Output data;
   toout=time||p_j`||a_j`||data||yyy;
   varnames={'time' 'p_j1' 'p_j2' 'a_j1' 'a_j2' 'data' 'yrmon'};
   create work.smoothf from toout[colname=varnames];
   append from toout;
* Output variance matrices in vectors;
   varout=C_out||R_out;
   varnames={'C_j_vec' 'R_j_vec'};
   create work.fvar from varout[colname=varnames];
   append from varout;
quit;

* Backward sweep of Kalman filter;
proc iml;
   use work.smoothf var {time p_j1 p_j2 a_j1 a_j2 data yrmon};
   read all;
   use work.fvar var {C_j_vec R_j_vec};
   read all;
   n=nrow(time)-1;
   p_j=p_j1`//p_j2`;
   a_j=a_j1`//a_j2`;
* DLM matrices;
   delta=1; G={1 1,0 1}; G[1,2]=delta;
   h_j=J(2,n+1,0); alpha_j=J(2,n+1,0);
   B_j=J(2,2,0); HH_j=J(2,2,0);
* Initial alpha sample;
   C_j=shape(C_j_vec[((n-1)*4)+1:(n*4),],2,2);
   alpha_j[1,n+1]=(normal(0)*sqrt(C_j[1,1]))+p_j[1,n+1];
   alpha_j[2,n+1]=(normal(0)*sqrt(C_j[2,2]))+p_j[2,n+1];
* Iterate backwards in time;
   do t=n to 1 by -1;
      C_j=shape(C_j_vec[((t-1)*4)+1:(t*4),],2,2);
      R_j=shape(R_j_vec[(t*4)+1:((t+1)*4),],2,2);
	  B_j=C_j*(G`)*inv(R_j);
	  HH_j=C_j-(B_j*R_j*(B_j`));
	  h_j[,t]=p_j[,t]+(B_j*(alpha_j[,t+1]-a_j[,t+1]));
* Sample alpha_j from a bivariate Normal;
* Sampling using Cholesky;
      normrnd=J(2,1,0);
      L=root(HH_j)`;
      do j=1 to 2;
	     normrnd[j,1]=normal(0);
	  end;
      do j=1 to 2;
         alpha_j[j,t]=(L[j,]*normrnd)+h_j[j,t];
	  end;
   end;
** Estimate sigma and tau;
* sigma;
   mse=J(n,1,0);
   do t=2 to n+1;
      mse[t-1,1]=(data[t,1]-alpha_j[1,t])**2;
   end;
   b=mse[+,]/2;
   a=n/2;
   toout=a||b;
   varnames={'a' 'b'};
   create work.siginfo from toout[colname=varnames];
   append from toout;
* Output data;
   toout=time||(alpha_j[1,]`)||(alpha_j[2,]`)||data||yrmon;
   varnames={'time' 'alpha_j' 'alpha_j2' 'data' 'yrmon'};
   create work.smoothb from toout[colname=varnames];
   append from toout;
quit;
* Update sigma from inverse gamma;
%ingamrnd(work.siginfo);
data work.sigma(drop=gamrnd);
   set work.gamup;
   sigma=sqrt(gamrnd);
   run=&run.;
run;
data work.smooth;
   set work.smoothb;
   if time>0;
   run=&run.;
run;
%mend kalfil;

* Macro to call Kalman filter repeatedly;
%macro runfil(cent,repunit,taurat);
* Get initial values for sigma;
data work.centre;
   set work.addtime;
   if centre=&cent. and runit=&repunit.; 
   yrmon=yronset-1900+((mthonset-1)/12);
*   ratestd=log(ratestd); * Examine log rates;
run;
proc univariate data=work.centre noprint;
   var ratestd;
   output out=work.sigma std=sigma;
run;
data work.sigch;
   set work.sigma;
   run=0;
run;
data work.allsmooth;
   time=0; run=0; data=0; alpha_j=0; alpha_j2=0; yrmon=0;
run;
%do count=1 %to 5000; *<-number of MCMC runs;
   %kalfil(&taurat.,&count.); *< tau ratio;
   proc append base=work.sigch data=work.sigma;
   run;
* Append smooth estimates;
   proc append base=work.allsmooth data=work.smooth;
   run;
%end;
* Output sigma information;
*%cntrname(&cent.,&repunit.);
title3 sigma mean and s.d.;
data work.burn;
   set work.sigch;
   if run > 500; *burn-in;
   centre=&cent.;
   runit=&repunit.;
run;
proc univariate data=work.burn noprint;
   by centre runit;
   var sigma;
   output out=work.sigstat std=std mean=mean;
run;
proc print data=work.sigstat noobs;
run;

** Plot;
data work.burnsm;
   set work.allsmooth;
   if run > 500; *burn-in;
   centre=&cent.;
   runit=&repunit.;
run;
* Get the MCMC based limits;
proc sort data=work.burnsm;
   by centre runit yrmon;
proc univariate data=work.burnsm noprint;
   by centre runit yrmon;
   var alpha_j;
   output out=work.smlimits pctlpre=p pctlpts=(2.5 97.5) mean=trend;
run;
* Calculate residuals for seasonal analysis;
data work.res;
   merge work.smlimits work.centre(keep=ratestd yrmon rename=(ratestd=data));
   by yrmon;
   errs=data-trend;
run;
goptions reset=all ftext=centx htext=3 gunit=pct colors=(black) border;
*filename graph1 "C:\temp\l&cent._&repunit..eps";
*goptions reset=all ftext=centx htext=3 gunit=pct colors=(black) border gunit=pct noborder
    gsfname=graph1 noprompt gsfmode=replace device=PSLEPSFC;
symbol1 i=join value=NONE color=black; 
symbol2 i=join value=NONE color=black line=2; 
symbol3 i=join value=NONE color=dagray; 
axis1 minor=NONE label=NONE;
axis2 minor=NONE label=NONE;
%cntrname(&cent.,&repunit.);
proc gplot data=work.res;
   plot trend*yrmon=1 p2_5*yrmon=2 p97_5*yrmon=2 data*yrmon=3 / overlay haxis=axis1 vaxis=axis2 noframe;
run; quit;
* Append errors and trend;
proc append base=work.allfilt data=work.res;
run;
* Make overall file of sigma values; 
%mend runfil;


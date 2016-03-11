function mGlobe_calc_Ocean(Input,output_file,output_file_type,start_calc,end_calc,step_calc,ghc_treshold,ghc_path,model_version,subtract_average,mean_field,pressure_time_series)
%MGLOBE_CALC_OCEAN Main function for the estimation of non-tidal ocean effect
% Function uses inputs generated by the main (GUI) mGlobe function and
% calculates the non-tidal ocean effect in nm/s^2.
% 
% INPUT:
%   Input             ... Point of observation 
%                         [Latitude (deg), Longitude (deg), Height(deg)]
%						              Example: [48.24885,16.35650,192.70]
%   output_file       ... full output file name
%						              Example: 'OCEAN_ECCO1_Effect.txt'
%   output_file_type  ... File type switch: [xls, txt, tsf]. xls not supported for Octave!
%						              Example: [0 1 0]
%   start_calc        ... starting time in matlab format (days)
%						              Example: datenum(2000,1,1,12,0,0)
%   end_calc          ... finish time in matlab format (days)
%						              Example: datenum(2001,1,1,12,0,0)
%   step_calc         ... time resolution switcher (not in time units)
%						              1 = 3 hours, 2 = 6 hours, 3 = 12 hours, 
%						               4 = one day, 5 = two days, 6 = month
%						              Example: 4
%   model_calc        ... Model intern identification/switch 
%						              1 = ECCO1, 2 = OTHER, 3 = GRACE,
%					                4 = ECCO2, 5 = OMCT_oba, 6 = OMCT_ocn,
%						              7 = OMCT_atm.
%						              Example: 1
%   ghc_treshold      ... minimal spherical distance of hydro.masses to the 
%                         point of observation in degrees
%						              Example: 0.1
%   ghc_path          ... path used for loading of model data
%						              Example: fullfile('OBPM','ECCO1')
%                         Example for Other models: 'OBPM\OTHER\OTHERmodel';
%                         Example for GRACE: 'GRACE\OCEAN\GRC_GFZ_RL05_OCEv1409s';
%   subtract_average  ... subtract average from all output variables 
%                         (0,1 = no, yes)
%						              Example: 0
%   mean_field        ... subtract pressure from each grid cell (similar to 
%						              mass conservation enforcement)
%						              1 = off
%                         2 = mean pressure of each time epoch will be
%                         subtracted. 
%                         3 = pressure time series will be used to correct
%                         each OBP model values
%						              Example: 2
%   pressure_time_series  cell array: {1} = full file name of the input
%                         pressure variation that will be used for the 
%                         subtraction of mean pressure (only if mean_fileld
%                         == 3)
%                         {2} = column number for matlab time
%                         {3} = column number for pressure variation (Pa)
%						              Example: mean_fileld ~=3: {[],[],[]}
%						              Example: mean_fileld = 3: {'OCEAN_OMCT_atm_Effect.txt',1,9}
% 
% OUTPUT (saved automatically): 
% date in matlab format, date civil, total effect, loading part of the
% effect, Newtonian part of the effect
% 
%                                         M.Mikolaj, mikolaj@gfz-potsdam.de
%                                                                18.06.2014
%                                                                      v1.0

tic
%% Set calculation properties
memory_mult = 1;                                                            % Change for low memory (RAM) PC (>1 lower resolution, <1 higher resolution)
% Zone 1
delta_zone1 = 0.15*memory_mult;                                             % resolution used in zone 1 (degrees), i.e. for point with spherical distance > treshold_zone1
treshold_zone1 = 14;                                                       	% degrees, threshold = spherical rectangle (for zone 1 to 4, zone 5 = spherical circle)
% Zone 2
delta_zone2 = 0.07*memory_mult;                                                         
treshold_zone2 = 2;
% Zone 3
delta_zone3 = 0.04*memory_mult;
treshold_zone3 = 1.05;
% Zone 4 & 5
delta_zone4 = 0.008*memory_mult;
delta_zone5 = 0.0008*memory_mult;
treshold_zone4out = 5;                                                      % this value must be more than the treshold_zone4 to the diff. between rectangle and circle border
if ghc_treshold>=0.1
    treshold_zone4in = ghc_treshold;
    treshold_zone5in = NaN;                                                 % if threshold>0.1 -> zone 5 will not be used
    treshold_zone5out = NaN;
else
    treshold_zone4in = 0.1;                                                 % if threshold<=0.1 -> zone 5 will be calculated up to given threshold (min 0.05 deg)
    treshold_zone5out = 0.1;
    treshold_zone5in = ghc_treshold;
end

%% Constant declaration
a = 6378137;                                                                % ellipsoidal major axis (m)
b = 6356752.314245;
e = sqrt((a^2-b^2)/a^2);
r = sqrt(1+2/3*e^2+3/5*e^4+4/7*e^6+5/9*e^8+6/11*e^10+7/13*e^12)*b;          % Radius of the replacement sphere -> equal surface
% Loading the table with deformation effect w.r.to spherical distance (according to (Pagiatakis,1988))
dgE_table = load('mGlobe_DATA_dgE_Hydro.txt');
dgE_table(:,1) = dgE_table(:,1)*pi/180;                                     % transform deg to radians

%% Time of observation
[year_s,month_s] = datevec(start_calc);                                     % transform matlab time to civil date
[year_e,month_e] = datevec(end_calc);
if step_calc == 6                                                           % create time for MONTHly data
    j = 1;
    for year = year_s:year_e
        if j == 1
            mz = month_s;
        else
            mz = 1;
        end
        if year == year_e
            mk = month_e;
        else
            mk = 12;
        end
        for m = mz:mk
            time(j,1) = year;
            time(j,2) = m;
            j = j + 1;
        end
    end
    time(:,3) = 1;
    time(:,7) = datenum(time(:,1),time(:,2),time(:,3));
else                                                                        % create time for other resolutions
    switch step_calc
        case 1
            time_resol_in_days = 3/24;
        case 2
            time_resol_in_days = 6/24;
        case 3 
            time_resol_in_days = 12/24;
        case 4
            time_resol_in_days = 1;
        case 5
            time_resol_in_days = 2;
    end
    days = start_calc:time_resol_in_days:end_calc;
    time = datevec(days);
    time(:,7) = days;
    clear days
end

if model_version == 3                                                       % special time treatment for GRACE data (=unequally spaced)
    clear time
    try
    cd(fullfile('GRACE','OCEAN'));
    file_count = dir([ghc_path(end-21:end),'*.mat']);                       % find files in GRACE folder with given PREFIX in *.mat format
    cd(fullfile('..','..'));
    if isempty(file_count)
        time(1,:) = [9999,9999,9999,9999,9999,9999,9999];
    else
        time(1:7,1:length(file_count)) = 0;
        for igrace = 1:length(file_count)
            time(igrace,1) = str2double(file_count(igrace).name(24:27));
            time(igrace,2) = str2double(file_count(igrace).name(28:29));
            time(igrace,3) = str2double(file_count(igrace).name(30:31));
            time(igrace,4) = str2double(file_count(igrace).name(33:34));
        end
        time(:,7) = datenum(time(:,1),time(:,2),time(:,3),time(:,4),0,0);   % transform to matlab time
        time(time(:,7)>end_calc,:) = [];                                    % calc. only with data specified by user (time)
        time(time(:,7)<start_calc,:) = [];              
        clear file_count igrace
        [temp_var,sort_id] = sort(time(:,7),1);                             % sort time (ascending)
        time = time(sort_id,:);                                             % sort time
    end
    catch
        set(findobj('Tag','text_status'),'String','Make sure that the GRACE folder does exist and contains desired files');drawnow % warn user
        fprintf('Make sure that the GRACE folder does exist and contains desired files\n')
        pause(5);
        clear time
        time(1,1:7) = [9999,9999,9999,9999,9999,9999,9999];
    end
end

%% Predefine variables
dgE(1:size(time,1),1:5) = 0;                                                % create variables for faster computation
dgP(1:size(time,1),1:5) = 0;
row_id_nan(1:size(time,1),1) = 0;
mean_value(1:size(time,1),1) = 0;

%% Load pressure time series if required
if mean_field == 3
   pressure_data = load(pressure_time_series{1});
else
    pressure_data = [];
end
%% CALCULATION
set(findobj('Tag','text_status'),'String','Ocean: Calculating non-tidal ocean effect...     '); drawnow % write status message to GUI
for i = 1:size(time,1);
    check_out = 0;
    %% Load Ocean model
    switch model_version                                                    % switch between supported models
        case 1
            model_name = 'ECCO1';
            obp_path = ghc_path;
        case 2
            model_name = ghc_path(end-9:end);                               % Other models, i.e. fix prefix
            obp_path = ghc_path(1:end-10);
        case 3
            model_name = ghc_path(end-21:end);                              % GRACE models, i.e. fix prefix
            obp_path = ghc_path(1:end-22);
        case 4
            model_name = 'ECCO2';
            obp_path = ghc_path;
        case 5 
            model_name = 'OMCT_oba';
            obp_path = ghc_path;
        case 6 
            model_name = 'OMCT_ocn';
            obp_path = ghc_path;
        case 7 
            model_name = 'OMCT_atm';
            obp_path = ghc_path;
    end
    switch model_version
        case 1
            if step_calc == 6
                nazov = fullfile(obp_path,sprintf('%s_M_%4d%02d.mat',model_name,time(i,1),time(i,2))); 
            else
                nazov = fullfile(obp_path,sprintf('%s_12H_%04d%02d%02d_%02d.mat',model_name,time(i,1),time(i,2),time(i,3),time(i,4)));
            end
        case 2 
            if step_calc == 6
                nazov = fullfile(obp_path,sprintf('%s_M_%4d%02d.mat',model_name,time(i,1),time(i,2))); 
            else
                nazov = fullfile(obp_path,sprintf('%s_D_%04d%02d%02d_%02d.mat',model_name,time(i,1),time(i,2),time(i,3),time(i,4)));
            end
        case 3 
            nazov = fullfile(obp_path,sprintf('%s_%04d%02d%02d_%02d.mat',model_name,time(i,1),time(i,2),time(i,3),time(i,4)));
        case 4
            if step_calc == 6
                nazov = fullfile(obp_path,sprintf('%s_M_%4d%02d.mat',model_name,time(i,1),time(i,2))); 
            else
                nazov = fullfile(obp_path,sprintf('%s_D_%04d%02d%02d_%02d.mat',model_name,time(i,1),time(i,2),time(i,3),time(i,4)));
            end
        otherwise
            nazov = fullfile(obp_path,sprintf('%s_6H_%04d%02d%02d_%02d.mat',model_name,time(i,1),time(i,2),time(i,3),time(i,4)));
    end
    try
        new = importdata(nazov);                                            % try to load OBP model
        switch model_version                                                % transform input model units to mm
            case 1
                new.celkovo = new.obp*100/(1027.5*9.81)*1000;               % input OBP in mbar (=*100 to Pa, = /(waterDensity*gravity) to meters*1000 to mm)  
            case 2
                new.celkovo = new.total;                                    % mm for other models
            case 3
                new.celkovo = new.total*10;                                 % input GRACE in cm
            case 4
                new.celkovo = new.obp*100/(1027.5*9.81)*1000;  
            otherwise
                new.celkovo = new.obp;
                new.lon(new.lon>=180) = new.lon(new.lon>=180) - 360;        % transform coordinates/longitude to (-180,180) system  
                ri = find(abs(diff(new.lon(1,:)))==max(abs(diff(new.lon(1,:)))));
                new.lon = horzcat(new.lon(:,ri+1:end),new.lon(:,1:ri));     % Connect matrices to remove discontinuity
            	  new.lat = horzcat(new.lat(:,ri+1:end),new.lat(:,1:ri));
                new.celkovo = horzcat(new.celkovo(:,ri+1:end),new.celkovo(:,1:ri));clear ri;
        end
        switch mean_field
            case 2
                if ~exist('delta_ghm','var')                                    % the grid is assumed to be constant in time
                    delta_ghm = [abs(new.lon(1,1)-new.lon(1,2)) abs(new.lat(1,1)-new.lat(2,1))];
                    delta_lat = diff(vertcat(new.lat(1,:)-delta_ghm(2),new.lat));
                    delta_lon = diff(horzcat(new.lon(:,1)-delta_ghm(1),new.lon)');delta_lon = delta_lon';
                    fiG = mGlobe_elip2sphere(new.lon*pi/180,new.lat*pi/180);        % transform given (ellipsoidal) coord. to spherical
                    delta_ghm_Sphere = abs(fiG+(delta_lat/2)*pi/180 - mGlobe_elip2sphere(new.lon*pi/180,(new.lat-delta_lat/2)*pi/180)); % calc. new grid resolution
                    area = 2*r^2*(delta_ghm(1)*pi/180).*cos(fiG).*sin(delta_ghm_Sphere./2);
                    total_area = sum(sum(area(~isnan(new.celkovo))));           % total area
                    clear fiG delta_ghm_Sphere delta_lat delta_lon             % remove used variables                    
                end
                mean_value(i,1) = sum(sum(new.celkovo(~isnan(new.celkovo)).*area(~isnan(new.celkovo))))./total_area; % weighted mean
            case 3
                mean_value(i,1) = (interp1(pressure_data(:,cell2mat(pressure_time_series{2})),pressure_data(:,cell2mat(pressure_time_series{3})),time(i,7))/(1027.5*9.81))*1000; % interpolate value and convert to mm
            case 1
                mean_value(i,1) = 0;
        end
        new.celkovo = new.celkovo - mean_value(i,1);                % subract the mean pressure if required
    catch
        out_message = sprintf('Ocean: file %s not found',nazov);            % warn user that the OBP model was not loaded
        set(findobj('Tag','text_status'),'String',out_message); drawnow
        fprintf('%s \n',out_message);
        check_out = 1;
    end
    if check_out == 0;
        delta_ghm = [abs(new.lon(1,1)-new.lon(1,2)) abs(new.lat(1,1)-new.lat(2,1))];
        
        %% FIRST ZONE
        z = 1;
        if ~exist('dgE1','var')                                             % initialization for the first zone
            boundries1 = [-180+delta_zone1/2 -90+delta_zone1/2;180-delta_zone1/2 90-delta_zone1/2];
            [dgE1,dgP1,la_out1,fi_out1,la_grid1,fi_grid1] = mGlobe_Global(Input(2),Input(1),boundries1,delta_zone1,dgE_table,r,treshold_zone1);
            [celkovo,DataID1] = mGlobe_interpolation(new.lon,new.lat,new.celkovo,la_grid1,fi_grid1,1); % interpolate water mass from GHM
        end
        celkovo = mGlobe_interpolation(new.lon,new.lat,new.celkovo,la_grid1,fi_grid1,0); % interpolate water mass from GHM
        celkovo(isnan(celkovo)) = 0;                                        % set continental areas to zero
        dgE(i,z) = sum(sum(dgE1(DataID1==-1).*celkovo(DataID1==-1)))*1e9;   % multiply and add all cells
        dgP(i,z) = sum(sum(dgP1(DataID1==-1).*celkovo(DataID1==-1)))*1e9;
        clear celkovo boundries1

        %% SECOND ZONE
        z = 2;
        if ~exist('dgE2','var')                                             % initialization for second zone
            boundries2 = [min(min(la_out1))-delta_zone1/2+delta_zone2/2  min(min(fi_out1))-delta_zone1/2+delta_zone2/2;...
                          max(max(la_out1))+delta_zone1/2-delta_zone2/2  max(max(fi_out1))+delta_zone1/2-delta_zone2/2];
            clear la_out1 fi_out1
            [dgE2,dgP2,la_out2,fi_out2,la_grid2,fi_grid2] = mGlobe_Global(Input(2),Input(1),boundries2,delta_zone2,dgE_table,r,treshold_zone2);
            [celkovo,DataID2] = mGlobe_interpolation(new.lon,new.lat,new.celkovo,la_grid2,fi_grid2,1); % interpolate water mass from GHM
        end
        celkovo = mGlobe_interpolation(new.lon,new.lat,new.celkovo,la_grid2,fi_grid2,0); % interpolate water mass from GHM
        celkovo(isnan(celkovo)) = 0;                                        % set continental areas to zero
        dgE(i,z) = sum(sum(dgE2(DataID2==-1).*celkovo(DataID2==-1)))*1e9;   % multiply and add all cells
        dgP(i,z) = sum(sum(dgP2(DataID2==-1).*celkovo(DataID2==-1)))*1e9;
        clear celkovo boundries2

        %% THIRD ZONE
        z = 3;
        if ~exist('dgE3','var')                                             % initialization for third zone
            boundries3 = [min(min(la_out2))-delta_zone2/2+delta_zone3/2  min(min(fi_out2))-delta_zone2/2+delta_zone3/2;...
                          max(max(la_out2))+delta_zone2/2-delta_zone3/2  max(max(fi_out2))+delta_zone2/2-delta_zone3/2];
            clear la_out2 fi_out2
            [dgE3,dgP3,la_out3,fi_out3,la_grid3,fi_grid3] = mGlobe_Global(Input(2),Input(1),boundries3,delta_zone3,dgE_table,r,treshold_zone3);
            [celkovo,DataID3] = mGlobe_interpolation(new.lon,new.lat,new.celkovo,la_grid3,fi_grid3,1); % interpolate water mass from GHM
        end
        celkovo = mGlobe_interpolation(new.lon,new.lat,new.celkovo,la_grid3,fi_grid3,0); % interpolate water mass from GHM
        celkovo(isnan(celkovo)) = 0;                                        % set continental areas to zero
        dgE(i,z) = sum(sum(dgE3(DataID3==-1).*celkovo(DataID3==-1)))*1e9;   % multiply and add all cells
        dgP(i,z) = sum(sum(dgP3(DataID3==-1).*celkovo(DataID3==-1)))*1e9;
        clear celkovo boundries3

        %% FOURTH ZONE
        z = 4;
        if ~exist('dgE4','var')                                             % initialization for the fourth zone
            boundries4 = [min(min(la_out3))-delta_zone3/2+delta_zone4/2  min(min(fi_out3))-delta_zone3/2+delta_zone4/2;...
                          max(max(la_out3))+delta_zone3/2-delta_zone4/2  max(max(fi_out3))+delta_zone3/2-delta_zone4/2];
            clear la_out3 fi_out3
            [dgE4,dgP4,la_out4,fi_out4,la_grid4,fi_grid4] = mGlobe_Local(Input(2),Input(1),Input(3),[],boundries4,delta_zone4,dgE_table,r,treshold_zone4in,treshold_zone4out);
            dgP4(isnan(dgP4)) = 0;
            [celkovo,DataID4] = mGlobe_interpolation(new.lon,new.lat,new.celkovo,la_grid4,fi_grid4,1); % interpolate water mass from GHM
        end
        celkovo = mGlobe_interpolation(new.lon,new.lat,new.celkovo,la_grid4,fi_grid4,0); % interpolate water mass from GHM
        celkovo(isnan(celkovo)) = 0;                                        % set continental areas to zero
        dgE(i,z) = sum(sum(dgE4(DataID4==-1).*celkovo(DataID4==-1)))*1e9;   % multiply and add all cells
        dgP(i,z) = sum(sum(dgP4(DataID4==-1).*celkovo(DataID4==-1)))*1e9;
        clear celkovo DataID

        %% FIFTH ZONE
        z = 5;
        if ghc_treshold < 0.1 
            if ~exist('dgE5','var')                                         % initialization for fifth zone
                boundries5 = [min(min(la_out4))-delta_zone4/2+delta_zone5/2  min(min(fi_out4))-delta_zone4/2+delta_zone5/2;...
                              max(max(la_out4))+delta_zone4/2-delta_zone5/2  max(max(fi_out4))+delta_zone4/2-delta_zone5/2];
                clear la_out4 la_out4 fi_out4 fi_out4
                [dgE5,dgP5,la_out5,fi_out5,la_grid5,fi_grid5] = mGlobe_Local(Input(2),Input(1),Input(3),[],boundries5,delta_zone5,dgE_table,r,treshold_zone5in,treshold_zone5out);
                dgP5(isnan(dgP5)) = 0;
                clear la_out5 fi_out5
                [celkovo,DataID5] = mGlobe_interpolation(new.lon,new.lat,new.celkovo,la_grid5,fi_grid5,1); % interpolate water mass from GHM
            end
            celkovo = mGlobe_interpolation(new.lon,new.lat,new.celkovo,la_grid5,fi_grid5,0); % interpolate water mass from GHM
            celkovo(isnan(celkovo)) = 0;                                    % set continental areas to zero
            dgE(i,z) = sum(sum(dgE5(DataID5==-1).*celkovo(DataID5==-1)))*1e9; % multiply and add all cells
            dgP(i,z) = sum(sum(dgP5(DataID5==-1).*celkovo(DataID5==-1)))*1e9;
            clear celkovo
        end 
        if size(time,1) > 2
            out_message = sprintf('Ocean: Calculating non-tidal ocean loading effect ... (%3.0f%%)',100*((i-1)/size(time,1))); % create message
        else
            out_message = sprintf('Ocean: Calculating non-tidal ocean loading effect ...'); % create message
        end
        set(findobj('Tag','text_status'),'String',out_message); drawnow     % write message to GUI
        clear new
    else
            row_id_nan(i) = 1;
            set(findobj('Tag','text_status'),'String',[nazov,' not found => left out!']); % warn user
%             fprintf('%s not found => left out!\n',nazov);
    end
end
if step_calc == 6 && model_version ~=3                                      % set accurate time (midpoint) for monthly data
    for ti = 1:size(time,1);
        time(ti,7) = (time(ti,7)+datenum(time(ti,1),time(ti,2)+1,1)-1)/2;   % rewrite existing time to accurate value
    end
    time(:,1:6) = datevec(time(:,7));
end
output_file_type(1) = 0;                                                    % force no xls output
if sum(sum(abs(dgE(~isnan(dgE))))) > 0
    %% Clear used variables and prepare results
    clear la_grid1 fi_grid1 la_grid2 fi_grid2 la_grid3 fi_grid3 la_grid5 fi_grud5 la_grid6 fi_grid6 DataID1 DataID2 DataID3 DataID4 DataID5
    total(:,1:5) = dgE(:,1:5) + dgP(:,1:5);
    total_write = -sum(total,2);
    dgE_write = -sum(dgE,2);
    dgP_write = -sum(dgP,2);
    total_write(row_id_nan == 1) = NaN;
    dgE_write(row_id_nan == 1) = NaN;
    dgP_write(row_id_nan == 1) = NaN;
    mean_value(row_id_nan == 1) = NaN;
    mean_value = mean_value*(1027.5*9.81)/1000;                             % Convert back to pressure (from mm)
    if subtract_average == 1
        dgE_write = dgE_write - mean(dgE_write(~isnan(dgE_write)));
        dgP_write = dgP_write - mean(dgP_write(~isnan(dgP_write)));
        total_write = total_write - mean(total_write(~isnan(total_write)));
    end
%     save([output_file(1:end-4) '.mat'],'total','dgE','dgP','time');
    %% Output xls
    duration = toc;
    set(findobj('Tag','text_status'),'String','Writing output file...');drawnow
    clear la_out fi_out DEM5 geoid nazov
    if output_file_type(1) == 1
        try
        table = {'Results of the non-tidal ocean loading effect calculation'};
        table(2,1:4) = {'Coord.:','phi','lambda','height'};
        table(3,1) = {'Station'};
        table(3,2) = num2cell(Input(1)); table(3,3) = num2cell(Input(2)); 
        table(3,4) = num2cell(Input(3));
        table(4,1) = {'Calculation settings:'}; 
        table(5,1) = {'no DEM'};
        table(6,1) = {'Excluded area:'};
        table(6,3) = {'nothing excluded'};
        table(7,1) = {'Model:'};table(7,3) = {model_name};
        table(8,1) = {'Model res.:'};
        table(8,3) = {sprintf('%3.2fx%3.2f deg',delta_ghm(1),delta_ghm(2))};
        if step_calc == 6
            table(8,4) = {'Monthly'};
        else
            table(8,4) = {'Daily/hourly'};
        end
        table(9,1) = {'Mass conservation:'};
        switch mean_field
            case 1
            table(9,3) = {'off'};
            case 2
            table(9,3) = {'Computed area average subtracted'};
            case 3
            table(9,3) = {sprintf('Given pressure subtracted %s',pressure_time_series(1))};
        end
        table(10,1) = {'GHE/LHE threshold (deg):'};
        table(10,3) = num2cell(ghc_treshold);
        table(11,1) = {'Calc. date:'};
        table(11,2:7) = num2cell(clock);
        table(12,1) = {'Calc. duration (min):'};
        table(12,3) = num2cell(duration/60);
        table(13,1) = {'Flagged value: empty cell'};
        table(14,1) = {'Results (in nm/s^2)'};
        table(15,1:13) = {'time_matlab','year','month','day','hour','minute','second','total_effect','continet_loading','continent_newton','ocean_loading','ocean_newton','subtracted_pressure(Pa)'};
        if size(time(:,7),1) >=65536                                        % write xls only if the total number of rows < max allowed Excel length
            output_file_type(2) = 1;                                        % in such case, the results will be written only to txt/tsoft format
            table(15,1) = {'Data to long for excel file-for results,see created txt file'};
            output_file_xls = output_file(1:end-4); 
            xlswrite([output_file_xls '.xls'],table);
        else
            table(16:16+size(total,1)-1,1) = num2cell(time(:,7));
            table(16:16+size(total,1)-1,2:7) = num2cell(datevec(time(:,7)));
            table(16:16+size(total,1)-1,8) = num2cell(total_write);
            table(16:16+size(total,1)-1,9) = num2cell(zeros(length(time(:,7)),1));
            table(16:16+size(total,1)-1,10) = num2cell(zeros(length(time(:,7)),1));
            table(16:16+size(total,1)-1,11) = num2cell(dgE_write);
            table(16:16+size(total,1)-1,12) = num2cell(dgP_write);
            table(16:16+size(total,1)-1,13) = num2cell(mean_value);
            output_file_xls = output_file(1:end-4);
            xlswrite([output_file_xls '.xls'],table);
        end
        catch
            set(findobj('Tag','text_status'),'String','Ocean: Could not write xls file (see *.txt for results)...');drawnow
            fprintf('Ocean: Could not write xls file (see *.txt for results)...\n');
            output_file_type(2)=1;
        end
    end
    %% Output txt
    if output_file_type(2) == 1    
        try
        output_file_txt = output_file(1:end-4);
        fid = fopen([output_file_txt '.txt'],'w');
        fprintf(fid,'%% Results of the non-tidal ocean loading effect calculation\n');
        fprintf(fid,'%% Station latitude (deg):   \t%10.8f\n',Input(1));
        fprintf(fid,'%% Station longitude (deg):   \t%10.8f\n',Input(2));
        fprintf(fid,'%% Station height (m):       \t%8.3f\n',Input(3));
        fprintf(fid,'%% Calculation settings:\n'); 
        fprintf(fid,'%% No DEM\n');
        fprintf(fid,'%% Nothing Excluded\n');
        fprintf(fid,'%% Model:\t %s\n',model_name);
        fprintf(fid,'%% Model resolution:\t%3.2fx%3.2f deg, ',delta_ghm(1),delta_ghm(2));
        if step_calc == 6
            fprintf(fid,'Monthly\n');
        else 
            fprintf(fid,'Daily/hourly\n');
        end
        fprintf(fid,'%% Mass conservation:\t');
        switch mean_field
            case 1
            fprintf(fid,'off\n');
            case 2
            fprintf(fid,'Computed area average subtracted\n');
            case 3
            fprintf(fid,'Given pressure subtracted %s\n',pressure_time_series{1});
        end
        fprintf(fid,'%% GHE/LHE threshold (deg):\t%5.2f\n',ghc_treshold);
        ctime = clock;
        fprintf(fid,'%% Calc. date:\t%04d/%02d/%02d %02d:%02d:%02d\n',ctime(1),ctime(2),ctime(3),ctime(4),ctime(5),round(ctime(6)));
        fprintf(fid,'%% Calculation duration (min):\t%5.2f\n',duration/60);
        fprintf(fid,'%% Flagged values: NaN\n');
        fprintf(fid,'%% Result units: nm/s^2\n');
        fprintf(fid,'%% time_matlab   \tDate       \tTime	 total_eff	 cont_load	 cont_newton	 ocean_load	 ocean_newton   subtracted_press(Pa)\n');
        [year,month,day,hour,minute,second] = datevec(time(:,7));
        for i = 1:length(time(:,7));
        fprintf(fid,'%12.6f   \t%4d%02d%02d   \t%02d%02d%02d\t\t%7.2f\t\t%7.2f\t\t%7.2f\t\t%7.2f\t\t%7.2f\t\t%12.2f\n',...
            time(i,7),year(i),month(i),day(i),hour(i),minute(i),second(i),...
            total_write(i),0,0,dgE_write(i),...
            dgP_write(i),mean_value(i,1));
        end
        fclose('all');
        catch
            set(findobj('Tag','text_status'),'String','Ocean: Could not write txt file...');drawnow
        end
    end
    %% Output tsf
    if output_file_type(3) == 1  
        try
        output_file_tsf = output_file(1:end-4);
        fid = fopen([output_file_tsf '.tsf'],'w');
        fprintf(fid,'[TSF-file] v01.0\n\n');
        fprintf(fid,'[UNDETVAL] 1234567.89\n\n');
        total_write(row_id_nan == 1) = 1234567.89;
        dgE_write(row_id_nan == 1) = 1234567.89;
        dgP_write(row_id_nan == 1) = 1234567.89;
        sum_for_tsf = total_write;
        sum_for_tsf(row_id_nan == 1) = 1234567.89;
        fprintf(fid,'[TIMEFORMAT] DATETIME\n\n');
        fprintf(fid,'[INCREMENT] %8.3f\n\n',time_resol_in_days*24*60*60);
        fprintf(fid,'[CHANNELS]\n');
        fprintf(fid,' Location:%s:total_effect\n',model_name); 
        fprintf(fid,' Location:%s:continental_loading_effect\n',model_name); 
        fprintf(fid,' Location:%s:continental_newtonian_effect\n',model_name); 
        fprintf(fid,' Location:%s:ocean_loading_effect\n',model_name); 
        fprintf(fid,' Location:%s:ocean_newtonian_effect\n',model_name); 
        fprintf(fid,' Location:%s:subtracted_pressure\n\n',model_name); 
        fprintf(fid,'[UNITS]\n nm/s^2\n nm/s^2\n nm/s^2\n nm/s^2\n nm/s^2\n Pa\n\n');
        fprintf(fid,'[COMMENT]\n');
		fprintf(fid,' Results of the non-tidal ocean loading effect calculation\n');
        fprintf(fid,' Station latitude (deg):   \t%10.8f\n',Input(1));
        fprintf(fid,' Station longitude (deg):   \t%10.8f\n',Input(2));
        fprintf(fid,' Station height (m):       \t%8.3f\n',Input(3));
        fprintf(fid,' Calculation settings:\n'); 
        fprintf(fid,' No DEM\n');
        fprintf(fid,' Nothing Excluded\n');
        fprintf(fid,' Model:\t %s\n',model_name);
        fprintf(fid,' Model resolution:\t%3.2fx%3.2f deg, ',delta_ghm(1),delta_ghm(2));
        if step_calc == 6
            fprintf(fid,'Monthly\n');
        else 
            fprintf(fid,'Daily/hourly\n');
        end
        fprintf(fid,' Mass conservation:\t');
        switch mean_field
            case 1
            fprintf(fid,'off\n');
            case 2
            fprintf(fid,'Computed area average subtracted\n');
            case 3
            fprintf(fid,'Given pressure subtracted %s\n',pressure_time_series{1});
        end
        fprintf(fid,' GHE/LHE threshold (deg):\t%5.2f\n',ghc_treshold);
        ctime = clock;
        fprintf(fid,' Calc. date:\t%04d/%02d/%02d %02d:%02d:%02d\n\n',ctime(1),ctime(2),ctime(3),ctime(4),ctime(5),round(ctime(6)));
        fprintf(fid,'[COUNTINFO] %8.0f\n\n',length(time(:,7)));
        fprintf(fid,'[DATA]\n');
        [year,month,day,hour,minute,second] = datevec(time(:,7));clear i
        for i = 1:length(time(:,7));
        fprintf(fid,'%04d %02d %02d  %02d %02d %02d   %17.3f %17.3f %17.3f %17.3f %17.3f %17.3f\n',...
            year(i),month(i),day(i),hour(i),minute(i),second(i),...
            sum_for_tsf(i),0,0,dgE_write(i),...
            dgP_write(i),mean_value(i,1));
        end
        fclose('all');
        catch
            set(findobj('Tag','text_status'),'String','Ocean: Could not write tsf file...');drawnow
        end
    end
    set(findobj('Tag','text_status'),'String','Ocean: NTOL calculated...');drawnow % write final message
else
    set(findobj('Tag','text_status'),'String','Ocean: No results obtained...(no ocean model input)');drawnow  
end


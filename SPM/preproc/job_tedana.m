function [ job ] = job_tedana( meinfo, prefix, outdir, mask, par )
%JOB_TEDANA
%
% Usual workflow is :
% - job_sort_echos
% - job_afni_proc_multi_echo
% - JOB_TEDANA
%
% Inputs :
% - REQUIRED meinfo  : generated by job_sort_echos
% - REQUIRED prefix  : prefix added by job_afni_proc_multi_echo depending on the blocks, default is 'vt' for raw -> (t)imeshift -> (v)olreg
% - OPTIONAL outidir : [] or char or cellstr
% - OPTIONAL mask    : []         or cellstr
% - OPTIONAL par     : classic matvol parameter structure
%
% Notes :
% - outdir : []      -> same dir as first echo
%            char    -> will be /path/to/first-echo/<outdir>
%            cellstr -> you give the list
%
% - mask   : []      -> no mask, tedana will compute it automatically
%            char    -> will be /path/to/first-echo/<mask>
%            cellstr -> you give the list
%
%
% See also job_sort_echos job_afni_proc_multi_echo

if nargin==0, help(mfilename), return, end


%% Check input arguments

narginchk(2,5)

if ~exist('par','var')
    par = ''; % for defpar
end

if ~exist('outdir','var')
    outdir = [];
end

if ~exist('mask','var')
    mask = [];
end

if isfield(meinfo,'volume')
    obj = 1;
else
    obj = 0;
end


%% defpar

% tedana.py main arguments
defpar.tedpca     = ''; % mle, kundu, kundu-stabilize (tedana default = mle)
defpar.maxrestart = []; % (tedana default = 10)
defpar.maxit      = []; % (tedana default = 500)
defpar.png        = 1;  % tedana will make some PNG files of the components Beta map, for quality checks

% tedana.py other arguments
defpar.cmd_arg = ''; % Allows you to use all addition arguments not scripted in this job_tedana.m file

% matvol classic options
defpar.pct          = 0; % Parallel Computing Toolbox, will execute in parallel all the subjects
defpar.redo         = 0; % overwrite previous files
defpar.fake         = 0; % do everything exept running
defpar.verbose      = 2; % 0 : print nothing, 1 : print 2 first and 2 last messages, 2 : print all
defpar.auto_add_obj = 1;

% Cluster
defpar.sge      = 0;               % for ICM cluster, run the jobs in paralle
defpar.jobname  = 'job_tedana';
defpar.walltime = '08:00:00';      % HH:MM:SS
defpar.mem      = 16000;           % MB
defpar.sge_queu = 'normal,bigmem'; % use both

par = complet_struct(par,defpar);


%% Setup that allows this scipt to prepare the commands only, no execution

parsge  = par.sge;
par.sge = -1; % only prepare commands

parverbose  = par.verbose;
par.verbose = 0; % don't print anything yet


%% Expand meinfo path & TE

% Strip down the echo data
echos = [meinfo.data{:}];
echos = echos(:);
echos = cell2mat(echos);

% path of serie
pth = cell(size(echos,1),1);
for e = 1 : size(echos,1)
    pth{e} = {echos(e,:).fname};
    pth{e} = addprefixtofilenames(pth{e},prefix);
end

% TEs associated
TE = cell(size(echos,1),1);
for e = 1 : size(echos,1)
    TE{e} = [echos(e,:).TE];
end


%% Main

nJobs = length(pth);

job = cell(nJobs,1); % pre-allocation, this is the job containter

skip  = [];
for iJob = 1 : nJobs
    
    % Extract subject name, and print it
    run_path = get_parent_path( pth{iJob}{1} );
    working_dir = run_path;
    
    % Prepare outdir & mask if needed
    if ~isempty(outdir)
        switch class(outdir)
            case 'char'
                outdir_path = fullfile(working_dir,outdir);
            case 'cell'
                outdir_path = outdir{iJob};
            otherwise
                error('outdir must be char our cellstr')
        end
    else
        outdir_path = working_dir;
    end
    if ~isempty(mask)
        switch class(mask)
            case 'char'
                mask_path = fullfile(working_dir,mask);
            case 'cell'
                mask_path = mask{iJob};
            otherwise
                error('mask must be char our cellstr')
        end
    else
        mask_path = '';
    end
    
    % Already done processing ?
    if ~par.redo  &&  exist(fullfile(outdir_path,'dn_ts_OC.nii'),'file') == 2
        fprintf('[%s]: skiping %d/%d @ %s because %s exist \n', mfilename, iJob, nJobs, outdir_path, 'dn_ts_OC.nii');
        jobchar = '';
        skip = [skip iJob];
    else
        % Echo in terminal & initialize job_subj
        fprintf('[%s]: Preparing JOB %d/%d for %s \n', mfilename, iJob, nJobs, run_path);
        jobchar = sprintf('#################### [%s] JOB %d/%d for %s #################### \n', mfilename, iJob, nJobs, run_path); % initialize
    end
    
    %-Prepare command : tedana
    %==================================================================
    
    data_sprintf = repmat('%s ',[1  length(pth{iJob})]);
    data_sprintf(end) = [];
    data_arg = sprintf(data_sprintf,pth{iJob}{:}); % looks like : "path/to/echo1, path/to/echo2, path/to/echo3"
    
    echo_sprintf = repmat('%g ',[1 length(TE{iJob})]);
    echo_sprintf(end) = [];
    echo_arg = sprintf(echo_sprintf,TE{iJob}); % looks like : "TE1, TE2, TE3"
    
    % Main command
    cmd = sprintf('mkdir -p %s; \n cd %s;\n tedana \\\\\n -e %s \\\\\n -d %s \\\\\n',...
        outdir_path, outdir_path, echo_arg, data_arg);
    
    % Save dir
    cmd =                              sprintf('%s --out-dir %s    \\\\\n', cmd, outdir_path   );
    
    % Options
    if par.png                 , cmd = sprintf('%s --png           \\\\\n', cmd                ); end
    if ~isempty(par.maxrestart), cmd = sprintf('%s --maxrestart %d \\\\\n', cmd, par.maxrestart); end
    if ~isempty(par.maxit     ), cmd = sprintf('%s --maxit %d      \\\\\n', cmd, par.maxit     ); end
    if ~isempty(mask_path     ), cmd = sprintf('%s --mask %s       \\\\\n', cmd, mask_path     ); end
    if ~isempty(par.tedpca    ), cmd = sprintf('%s --tedpca %s     \\\\\n', cmd, par.tedpca    ); end
    
    % Other args ?
    if ~isempty(par.cmd_arg)
        cmd = sprintf('%s %s \\\\\n', cmd, par.cmd_arg);
    end
    
    % Finish preparing tedana job
    cmd = sprintf('%s 2>&1 | tee tedana.log \n',cmd); % print the terminal output into a log file
    
    jobchar = [jobchar cmd]; %#ok<*AGROW>
    
    % Save job_subj
    job{iJob} = jobchar;
    
end % subj

% Now the jobs are prepared
job(skip) = [];


%% Run the jobs

% Fetch origial parameters, because all jobs are prepared
par.sge     = parsge;
par.verbose = parverbose;

% Run CPU, run !
job = do_cmd_sge(job, par);


%% Add outputs objects

if obj && par.auto_add_obj && (par.run || par.sge)
    
    volumes = meinfo.volume;
    series  = [volumes.serie];
    series  = unique(series);
    
    for iSer = 1 : length(series)
        
        ser = series(iSer);
        ech = echos(iSer,1);
        
        if par.run     % use the normal method
            
            if ~isempty(outdir) && ischar(outdir)
                ser.addVolume(outdir,    '^ts_OC.nii' ,    'ts_OC', 1 );
                ser.addVolume(outdir, '^dn_ts_OC.nii' , 'dn_ts_OC', 1 );
                ser.addVolume(outdir,      '^s0v.nii' ,      's0v', 1 );
                ser.addVolume(outdir,     '^t2sv.nii' ,     't2sv', 1 );
            elseif ~isempty(outdir) && iscellstr(outdir)
                error('not coded yet')
            else
                ser.addVolume(    '^ts_OC.nii' ,    'ts_OC', 1 );
                ser.addVolume( '^dn_ts_OC.nii' , 'dn_ts_OC', 1 );
                ser.addVolume(      '^s0v.nii' ,      's0v', 1 );
                ser.addVolume(     '^t2sv.nii' ,     't2sv', 1 );
            end
            
        elseif par.sge % add the new volume in the object manually, because the file is not created yet
            
            if ~isempty(outdir) && ischar(outdir)
                ser.volume(end + 1) = volume( fullfile(ser.path,outdir,[   'ts_OC' ech.ext]),    'ts_OC' , ser.exam, ser );
                ser.volume(end + 1) = volume( fullfile(ser.path,outdir,['dn_ts_OC' ech.ext]), 'dn_ts_OC' , ser.exam, ser );
                ser.volume(end + 1) = volume( fullfile(ser.path,outdir,[     's0v' ech.ext]),      's0v' , ser.exam, ser );
                ser.volume(end + 1) = volume( fullfile(ser.path,outdir,[    't2sv' ech.ext]),    'ts_OC' , ser.exam, ser );
            elseif ~isempty(outdir) && iscellstr(outdir)
                error('not coded yet')
            else
                ser.volume(end + 1) = volume( fullfile(ser.path,[   'ts_OC' ech.ext]),    'ts_OC' , ser.exam, ser );
                ser.volume(end + 1) = volume( fullfile(ser.path,['dn_ts_OC' ech.ext]), 'dn_ts_OC' , ser.exam, ser );
                ser.volume(end + 1) = volume( fullfile(ser.path,[     's0v' ech.ext]),      's0v' , ser.exam, ser );
                ser.volume(end + 1) = volume( fullfile(ser.path,[    't2sv' ech.ext]),    'ts_OC' , ser.exam, ser );
            end
            
        end % run / sge
        
    end % iSer
    
end % if


end % function

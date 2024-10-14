function [Recordings, Dataset, BidsFolder] = BidsRecordings(BidsFolder, Verbose, NoiseFirst)
    % Find MEG recordings and extract their metadata from a CTF MEG BIDS dataset.
    %
    % [Recordings, Dataset, BidsFolder] = BidsRecordings(BidsFolder, Verbose, NoiseFirst, SubOnly)
    %
    % The returned Recordings and optionally Dataset structures contains all BIDS metadata.  If the
    % provided BidsFolder is not the root BIDS folder, only recordings found under the provided
    % folder will be listed.  However, if it is not a subfolder of a BIDS dataset, an error is
    % returned. The returned BidsFolder is the root BIDS folder. Only the recordings found under
    % BidsRootFolder/sub-*/... are processed, not those under sourcedata or derivatives for example.
    % To process such a sub-dataset (e.g. sourcedata), it must contain a dataset_description.json
    % file and appear as a full valid BIDS dataset itself.
    %
    % If NoiseFirst is true, empty room noise recordings will be listed first. This is used for
    % associating noise recordings in other functions.
    %
    % Marc Lalancette, 2024-10-11
    
    % Dependencies
    BidsSetPath;
    
    if nargin < 3 || isempty(NoiseFirst)
        NoiseFirst = true;
    end
    if nargin < 2 || isempty(Verbose)
        Verbose = true;
    end
    
    % Find CTF recordings (*.ds) in this folder. 
    % This can take a few minutes for large datasets.
    if Verbose
        fprintf('Searching for recordings in BIDS folder...\n');
    end
    InputFolder = BidsFolder;
    % Find root BIDS folder.
    DataDescripFile = fullfile(BidsFolder, 'dataset_description.json');
    while ~exist(DataDescripFile, 'file')
        if isempty(BidsFolder) || strcmp(BidsFolder, filesep)
            error('BIDS root folder not found: missing dataset_description.json');
        end
        % Go up to parent directory.
        BidsFolder = fileparts(BidsFolder);
        DataDescripFile = fullfile(BidsFolder, 'dataset_description.json');
    end
    % Only process parts of the main BIDS dataset, not sub-datasets.
    if strcmp(InputFolder, BidsFolder) 
        RecordingsList = dir(fullfile(BidsFolder, 'sub-*', '**', '*.ds'));
    elseif contains(InputFolder, fullfile(BidsFolder, 'sub-'))
        RecordingsList = dir(fullfile(InputFolder, '**', '*.ds'));
    else
        error('Cannot process sub-dataset of main BIDS dataset, e.g. sourcedata or derivatives, unless it also has a dataset_description.json');
    end
    % Remove hz.ds 
    % I use contains to also remove my renamed ..._meghz.ds
    RecordingsList(contains({RecordingsList.name}, 'hz.ds', 'IgnoreCase', true)) = [];
    nR = numel(RecordingsList);

    if nR > 0
        % Pre-allocate, as a column.
        % Structures are *not* empty (only no fields) on purpose, so we can add fields.
        Recordings(nR,1) = struct('Name', '', 'Folder', '', 'Subject', '', 'Session', '', ...
            'Task', '', 'Acq', '', 'Run', '', 'isNoise', [], 'Scan', table(), ...
            'Meg', struct(), 'CoordSystem', struct(), 'Channels', table(), 'Events', table(), ...
            'Files', struct());
        
        if Verbose
            fprintf('Found %d recordings.\nReading recording     ', nR);
        end
    else
        Recordings = [];
    end
    ChanOpts = [];
    for r = 1:nR
        if Verbose
            fprintf('\b\b\b\b%4d', r);
        end
        Recordings(r).Name = RecordingsList(r).name;
        % Keep path relative to base folder.
        Recordings(r).Folder = strrep(RecordingsList(r).folder, BidsFolder, '');
        if Recordings(r).Folder(1) == filesep
            Recordings(r).Folder(1) = '';
        end
        
        % Extract basic info from file name.
        % BIDS: sub-<label>[_ses-<label>]_task-<label>[_acq-<label>][_run-<index>][_proc-<label>]_meg.<manufacturer_specific_extension>
        [isBids, RecNameInfo] = BidsParseRecordingName(Recordings(r).Name);
        for Field = {'Subject', 'Session', 'Task', 'Acq', 'Run'}
            Field = Field{1}; %#ok<FXSET>
            if isfield(RecNameInfo, Field)
                Recordings(r).(Field) = RecNameInfo.(Field);
            end
        end
        if ~isBids
            warning('Unrecognized recording name structure, expecting BIDS: %s', Recordings(r).Name);
            continue;
        end
        if contains(RecNameInfo.Subject, 'emptyroom') || strncmpi(RecNameInfo.Task, 'noise', 5)
            Recordings(r).isNoise = true;
        else
            Recordings(r).isNoise = false;
        end
        
        % Get scan date from scans.tsv file, so that it can more easily be
        % extended to anat or other modalities eventually.
        [RecPath, RecName, RecExt] = fileparts(fullfile(BidsFolder, Recordings(r).Folder, Recordings(r).Name));
        switch RecExt
            case '.ds'
                Modality = 'meg';
            case '.nii'
                Modality = 'anat';
            case '.gz'
                Modality = 'anat';
            otherwise
                error('Unrecognized modality: %s', RecExt);
        end
        ScansFile = fullfile(BidsFolder, ['sub-', Recordings(r).Subject], ['ses-', Recordings(r).Session], ...
            ['sub-', Recordings(r).Subject, '_ses-', Recordings(r).Session, '_scans.tsv']);
        if ~exist(ScansFile, 'file') 
            Recordings(r).Files.Scans = '';
            if Verbose
                warning('Missing scans.tsv file: %s', ScansFile);
            end
        else
            Recordings(r).Files.Scans = ScansFile;
            Scans = ReadScans(ScansFile);
            Filename = strrep(fullfile(Modality, Recordings(r).Name), '\', '/');
            iScan = find(strcmp(Scans.filename, Filename), 1); % this works even if Scans is empty and Scans.filename is class double.
            if isempty(iScan) 
                if Verbose
                    warning('Scan not found in session scans table: %s', Recordings(r).Name);
                end
                % (Empty (table or not) caused issues in BidsRebuildAllFiles, but that was a bug.)
                TempScan.filename = '';
                TempScan.acq_time = NaT(0);
                Recordings(r).Scan = struct2table(TempScan);
                % Recordings(r).Scan = {[], NaT}; % No it's not a table yet.
            else
                Recordings(r).Scan = Scans(iScan, :);
            end
        end
        
        % Get metadata from _meg.json file.
        MegFile = fullfile(RecPath, [RecName, '.json']);
        if ~exist(MegFile, 'file') 
            Recordings(r).Files.Meg = '';
            if Verbose
                warning('Missing meg.json file: %s', MegFile);
            end
        else
            Recordings(r).Files.Meg = MegFile;
            Fid = fopen(MegFile);
            Recordings(r).Meg = jsondecode(fread(Fid, '*char')');
            fclose(Fid);
        end
        
        % Get metadata from _coordsystem.json file.
        if Recordings(r).isNoise
            Recordings(r).Files.CoordSystem = '';
            Recordings(r).CoordSystem = struct();
        else
            CoordFile = fullfile(RecPath, ['sub-', Recordings(r).Subject, ...
                '_ses-', Recordings(r).Session, '_coordsystem.json']);
            if ~exist(CoordFile, 'file')
                CoordFile1 = CoordFile;
                % Look for coordinate files named with full recording name.
                CoordFile = fullfile(RecPath, [RecName(1:end-3), 'coordsystem.json']);
            end
            if ~exist(CoordFile, 'file')
                Recordings(r).Files.CoordSystem = '';
                if Verbose && ~Recordings(r).isNoise
                    % Optional file so inform but not a warning.
                    fprintf('Missing coordsystem file: %s\n', CoordFile1);
                end
            else
                Recordings(r).Files.CoordSystem = CoordFile;
                Fid = fopen(CoordFile);
                Recordings(r).CoordSystem = jsondecode(fread(Fid, '*char')');
                fclose(Fid);
            end
        end
        
        % Get metadata from _channels.tsv file.
        ChannelFile = fullfile(RecPath, [RecName(1:end-3), 'channels.tsv']);
        if ~exist(ChannelFile, 'file') 
            Recordings(r).Files.Channels = '';
            if Verbose
                % Optional file so inform but not a warning.
                fprintf('Missing channels file: %s\n', ChannelFile);
            end
        else
            Recordings(r).Files.Channels = ChannelFile;
            % Force text type to keep 'n/a' values.
            if isempty(ChanOpts)
                ChanOpts = detectImportOptions(ChannelFile, 'FileType', 'text');
                ChanOpts = setvartype(ChanOpts, {'low_cutoff', 'high_cutoff', 'notch'}, 'char');
            end
            Recordings(r).Channels = readtable(ChannelFile, ChanOpts);
        end

        % Get metadata from _events.tsv file.
        EventsFile = fullfile(RecPath, [RecName(1:end-3), 'events.tsv']);
        if ~exist(EventsFile, 'file') 
            Recordings(r).Files.Events = '';
            Recordings(r).Events = table('Size', [0, 5], 'VariableTypes', {'double', 'double', 'double', 'double', 'cellstr'}, ...
                'VariableNames', {'onset', 'duration', 'ds_trial', 'sample', 'value'});
            %if Verbose && ~Recordings(r).isNoise
            %    % Optional file so inform but not a warning.
            %    fprintf('Missing events file: %s\n', EventsFile);
            %end
        else
            Recordings(r).Files.Events = EventsFile;
            Recordings(r).Events = readtable(EventsFile, ...
                'FileType', 'text', 'Delimiter', '\t', 'ReadVariableNames', true);
        end
        
    end % recording loop
    
    if NoiseFirst && nR > 1
        % List noise recordings first.  For BidsRebuildAllFiles.
        Recordings = Recordings([find([Recordings.isNoise]), find(~[Recordings.isNoise])]);
    end
    
    % Also extract global metadata if requested.
    if nargout > 1
        % dataset_description.json was found earlier.
        Fid = fopen(DataDescripFile);
        Dataset.Dataset = jsondecode(fread(Fid, '*char')');
        fclose(Fid);
        Dataset.Files.Dataset = DataDescripFile;
        Dataset.BidsFolder = BidsFolder;
        IgnoreFile = fullfile(BidsFolder, '.bidsignore');
        if ~exist(IgnoreFile, 'file') 
            if Verbose
                fprintf('No optional file: %s\n', IgnoreFile);
            end
        else
            Fid = fopen(IgnoreFile);
            Dataset.Ignore = textscan(Fid, '%s', 'CommentStyle', '#', 'Delimiter', '\n');
            fclose(Fid);
            Dataset.Ignore = Dataset.Ignore{1};
            Dataset.Files.Ignore = IgnoreFile;
        end
    end
    if Verbose
        fprintf('\n');
    end

end



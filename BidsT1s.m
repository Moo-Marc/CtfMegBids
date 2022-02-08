function [Images, Dataset] = BidsT1s(BidsFolder, Verbose)
    % Extract all T1w image files and their metadata from a BIDS dataset.
    %
    % [Images, Dataset] = BidsT1s(BidsFolder)
    %
    % The returned Images structure
    %
    % BidsFolder is optional, '/meg/meg2/omega/OMEGA_BIDS' by default.
    %
    % Marc Lalancette, 2020-08-05
    
    %addpath('/meg/meg1/software/BIDS');
    
    if nargin < 2 || isempty(Verbose)
        Verbose = true;
    end
    if nargin < 1 || isempty(BidsFolder)
        BidsFolder = '/meg/meg2/omega/OMEGA_BIDS';
    end
    
    if ~exist(BidsFolder, 'dir')
        error('Folder not found: %s', BidsFolder);
    end
    % Find T1w MRIs (*_T1w.nii.gz) in this folder.
    ImageList = dir(fullfile(BidsFolder, '**', '*_T1w.nii*'));
    nI = numel(ImageList);
        
    Images(nI) = struct('Name', '', 'Folder', '', 'Subject', '', 'Session', '', ...
        'CE', '', 'Rec', '', 'Acq', '', 'Run', '', 'Scan', table(), ...
        'T1w', struct());
    
    fprintf('Found %d T1w MRI images.\nReading image     ', nI);
    for i = 1:nI
        fprintf('\b\b\b\b%4d', i);
        Images(i).Name = ImageList(i).name;
        % Keep path relative to base folder.
        Images(i).Folder = strrep(ImageList(i).folder, BidsFolder, '');
        if Images(i).Folder(1) == filesep
            Images(i).Folder(1) = '';
        end
        
        % Extract basic info from file name.
        % BIDS: sub-<label>[_ses-<label>][_acq-<label>][_ce-<label>][_rec-<label>][_run-<index>]_<modality_label>.nii[.gz]
        %       sub-<label>[_ses-<label>][_acq-<label>][_ce-<label>][_rec-<label>][_run-<index>][_mod-<label>]_defacemask.nii[.gz]
        if strncmp(Images(i).Name, 'sub-', 4) && ...
                contains(Images(i).Name, 'T1w') && ...
                contains(Images(i).Name, '.nii')
            Name = strrep(Images(i).Name, '.gz', '');
            Name = strrep(Name, '_T1w.nii', '');
            while ~isempty(Name)
                [Entity, Name] = strtok(Name, '-_');
                [ID, Name] = strtok(Name, '-_');
                if isempty(ID)
                    warning('Empty BIDS image name part: %s.', Entity);
                end
                switch Entity
                    case 'sub'
                        Images(i).Subject = ID;
                    case 'ses'
                        if isempty(ID)
                            warning('Empty session not yet supported.');
                        end
                        Images(i).Session = ID;
                    case 'ce'
                        Images(i).CE = ID;
                    case 'rec'
                        Images(i).Rec = ID;
                    case 'acq'
                        Images(i).Acq = ID;
                    case 'run'
                        Images(i).Run = ID;
                    otherwise
                        warning('Unrecognized BIDS anatomical image name entity: %s. %s', ...
                            Entity, Images(i).Name);
                end
            end
            % Kludge for heudiconv issue with no session in file names.
            if isempty(Images(i).Session)
                Images(i).Session = '0001';
            end
        else
            warning('Unrecognized image name structure, expecting BIDS: %s', Images(i).Name);
            continue;
        end
        
        % Get scan date from scans.tsv file, so that it can more easily be
        % extended to anat or other modality eventually.
        [ImPath, ImName, ImExt] = fileparts(fullfile(BidsFolder, Images(i).Folder, Images(i).Name));
        switch ImExt
            case '.ds'
                Modality = 'meg';
            case '.nii'
                Modality = 'anat';
            case '.gz'
                Modality = 'anat';
                [~, ImName] = fileparts(ImName);
            otherwise
                error('Unrecognized modality: %s', ImExt);
        end
        ScansFile = fullfile(BidsFolder, ['sub-', Images(i).Subject], ['ses-', Images(i).Session], ...
            ['sub-', Images(i).Subject, '_ses-', Images(i).Session, '_scans.tsv']);
        if ~exist(ScansFile, 'file') 
            % Kludge: try without session in file name (heudiconv issue).
            ScansFile = fullfile(BidsFolder, ['sub-', Images(i).Subject], ['ses-', Images(i).Session], ...
                ['sub-', Images(i).Subject, '_scans.tsv']);
        end
        if ~exist(ScansFile, 'file') 
            if Verbose
                warning('Missing scans.tsv file: %s', ScansFile);
            end
        else
            Images(i).Files.Scans = ScansFile;
            Scans = ReadScans(ScansFile);
            Filename = strrep(fullfile(Modality, Images(i).Name), '\', '/');
            iScan = find(strcmp(Scans.filename, Filename), 1); % this works even if Scans is empty and Scans.filename is class double.
            if isempty(iScan) 
                if Verbose
                    warning('Scan not found in session scans table: %s', Images(i).Name);
                end
                % (Empty (table or not) caused issues in BidsRebuildAllFiles, but that was a bug.)
                TempScan.filename = '';
                TempScan.acq_time = NaT(0);
                Images(i).Scan = struct2table(TempScan);
                % Images(r).Scan = {[], NaT}; % No it's not a table yet.
            else
                Images(i).Scan = Scans(iScan, :);
            end
        end
        
        % Get metadata from _T1w.json file.
        T1wFile = fullfile(ImPath, [ImName, '.json']);
        if ~exist(T1wFile, 'file') 
            if Verbose
                warning('Missing T1w.json file: %s', T1wFile);
            end
        else
            Fid = fopen(T1wFile);
            Images(i).T1w = jsondecode(fread(Fid, '*char')');
            fclose(Fid);
            Images(i).Files.T1w = T1wFile;
        end
        
    end % image loop
   
    % Also extract global metadata if requested.
    if nargout > 1
        DataDescripFile = fullfile(BidsFolder, 'dataset_description.json');
        if ~exist(DataDescripFile, 'file') 
            if Verbose
                warning('Missing file: %s', DataDescripFile);
            end
        else
            Fid = fopen(DataDescripFile);
            Dataset.Dataset = jsondecode(fread(Fid, '*char')');
            fclose(Fid);
            Dataset.Files.Dataset = DataDescripFile;
        end
        Dataset.BidsFolder = BidsFolder;
        IgnoreFile = fullfile(BidsFolder, '.bidsignore');
        if ~exist(IgnoreFile, 'file') 
            if Verbose
                fprintf('Missing file: %s\n', IgnoreFile);
            end
        else
            Fid = fopen(IgnoreFile);
            Dataset.Ignore = textscan(Fid, '%s', 'CommentStyle', '#', 'Delimiter', '\n');
            fclose(Fid);
            Dataset.Ignore = Dataset.Ignore{1};
            Dataset.Files.Ignore = IgnoreFile;
        end
    end
    fprintf('\n');

end



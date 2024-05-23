function BidsInfo = BidsBuildSessionFiles(Recording, BidsInfo, Overwrite, SaveFiles)
    % Create BIDS metadata files for a MEG session.
    % Satisfies BIDS version indicated in BidsBuildStudyFiles.
    %
    % Setting Overwrite = true does not replace the entire file, but
    % replaces an existing entry for the same recording.
    %
    % Authors: Elizabeth Bock 2017, Marc Lalancette, 2018 - 2022-01-10
    
    % TO DO: add T1 scan. Get scan date from MRI json?
    
    if nargin < 4 || isempty(SaveFiles)
        SaveFiles = true;
    end
    if nargin < 3 || isempty(Overwrite)
        Overwrite = false;
    end
    if nargin < 2 
        BidsInfo = [];
    end
    
    if nargout
        Output = true;
    else
        Output = false;
    end
    if ~SaveFiles && ~Output
        % Nothing to do.
        warning('Selected options leave nothing to do.');
        return;
    end
    
    % Dependencies
    BidsSetPath;
    
    [RecPath, RecName, RecExt] = fileparts(Recording);
    switch RecExt
        case '.ds'
            Modality = 'meg';
            Res4File = fullfile(RecPath, [RecName, RecExt], [RecName, '.res4']);
            Res4 = Bids_ctf_read_res4(Res4File);
            ScanDate = datetime([Res4.res4.data_date, ' ', Res4.res4.data_time]); 
            if ScanDate == datetime('1900-01-01 00:00:00') % Acq "date not set" bug.
                InfoDsFile = fullfile(RecPath, [RecName, RecExt], [RecName, '.infods']);
                InfoDs = CPersistToStruct(readCPersist(InfoDsFile, 0));
                ScanDate = datetime(InfoDs.DATASET_INFO.DATASET_COLLECTIONDATETIME, 'InputFormat', 'yyyyMMddhhmmss');
            end
        case {'.nii', '.gz'}
            Modality = 'anat';
            ScanDate = NaT;
            if ~isempty(BidsInfo) && isfield(BidsInfo, 'Date')
                % Temporary way to use this for anat too.
                ScanDate = BidsInfo.Date;
            end
        otherwise
            error('Unrecognized modality: %s', RecExt);
    end
    % TO DO: get scan date from MRI json?
    %             if isfield(BidsInfo, 'Date')
    %                 Date = BidsInfo.Date;
    %             else
    %                 Date = 'n/a';
    %             end
    
    % Convert \ to / on Windows.
    Scan.filename = {strrep(fullfile(Modality, [RecName, RecExt]), '\', '/')};
    Scan.acq_time = ScanDate;
    Scan = struct2table(Scan);    

    if isempty(BidsInfo)
       [~, BidsInfo] = BidsParseRecordingName([RecName, RecExt]);
    end
    iRelativePath = strfind(RecPath, [filesep, 'sub-']);
    BidsFolder = RecPath(1:iRelativePath(1)-1);
    ScansFile = fullfile(BidsFolder, ['sub-', BidsInfo.Subject], ['ses-', BidsInfo.Session], ...
        ['sub-', BidsInfo.Subject, '_ses-', BidsInfo.Session, '_scans.tsv']);

    if SaveFiles
        if exist(ScansFile, 'file')
            Scans = ReadScans(ScansFile);
            iScan = find(strcmp(Scan.filename, Scans.filename), 1); % This works even if Scans is empty and Scans.filename is class double.  ismember gives an error.
            if ~isempty(iScan)
                if Overwrite
                    Scans.acq_time(iScan) = Scan.acq_time;
                    % else % Scan already there, do nothing.
                end
            else
                Scans = [Scans; Scan];
            end
        else
            Scans = Scan;
            % struct2table(struct('filename', '', 'acq_time', NaT(0, 1))); % empty table
        end
        WriteScans(ScansFile, Scans);
    end
    if Output
        BidsInfo.Scan = Scan;
        BidsInfo.Files.Scans = ScansFile;
    end
    
end

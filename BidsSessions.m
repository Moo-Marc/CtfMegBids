function T = BidsSessions(BidsFolder, Verbose, ForceDateRead)
    % List sessions from BIDS dataset in table (Subject, Session, Date, ScansFile).
    %
    % SesTable = BidsSessions(BidsFolder, Verbose)
    %
    % Marc Lalancette, 2022-07-17
    
    if nargin < 2 || isempty(Verbose)
        Verbose = true;
    end
    if nargin < 3 || isempty(ForceDateRead)
        ForceDateRead = false;
    end
    
    % Only looks at first recording in each _scans.tsv file.
    SubSes = dir(fullfile(BidsFolder, 'sub-*', 'ses-*'));
    nSes = size(SubSes, 1);
    T = table('Size', [nSes, 5], 'VariableTypes', {'cellstr', 'cellstr', 'datetime', 'cellstr', 'logical'}, ...
        'VariableNames', {'Subject', 'Session', 'Date', 'ScansFile', 'Meg'});

    T.Session = replace({SubSes.name}', 'ses-', '');
    T.Subject = replace(replace({SubSes.folder}', [BidsFolder, filesep], ''), 'sub-', '');
    
    % Get session dates.
    for iSes = 1:nSes
        T.ScansFile{iSes} = fullfile(['sub-' T.Subject{iSes}], ['ses-' T.Session{iSes}], ...
            ['sub-', T.Subject{iSes}, '_ses-', T.Session{iSes}, '_scans.tsv']);
        MegFolder = fullfile(BidsFolder, ['sub-' T.Subject{iSes}], ['ses-' T.Session{iSes}], 'meg');
        if exist(MegFolder, 'dir')
            T.Meg(iSes) = true;
        else
            T.Meg(iSes) = false;
        end
        if ~exist(fullfile(BidsFolder, T.ScansFile{iSes}), 'file')
            if Verbose
                fprintf('Warning: Missing scans.tsv file: %s\n', T.ScansFile{iSes});
            end
            if ForceDateRead
                % Find one recording to get scan date.
                % Hack: Don't use BidsRecordings so it works on non-BIDS.
                %                 Recs = BidsRecordings(fullfile(BidsFolder, ['sub-' T.Subject{iSes}], ['ses-' T.Session{iSes}]));
                %                 if ~isempty(Recs)
                %                     T.Date(iSes) = Recs(1).Scan.Date(1);
                %                 end
                Recs = dir(fullfile(MegFolder, '*.ds'));
                if ~isempty(Recs)
                    Recs = fullfile(Recs(1).folder, Recs(1).name);
                    [RecPath, RecName, RecExt] = fileparts(Recs);
                    Res4File = fullfile(RecPath, [RecName, RecExt], [RecName, '.res4']);
                    Res4 = Bids_ctf_read_res4(Res4File);
                    T.Date(iSes) = datetime([Res4.res4.data_date, ' ', Res4.res4.data_time]);
                    if T.Date(iSes) == datetime('1900-01-01 00:00:00') % Acq "date not set" bug.
                        InfoDsFile = fullfile(RecPath, [RecName, RecExt], [RecName, '.infods']);
                        InfoDs = CPersistToStruct(readCPersist(InfoDsFile, 0));
                        T.Date(iSes) = datetime(InfoDs.DATASET_INFO.DATASET_COLLECTIONDATETIME, 'InputFormat', 'yyyyMMddhhmmss');
                    end
                end
            end
        else
            Scans = ReadScans(fullfile(BidsFolder, T.ScansFile{iSes}));
            if ~isempty(Scans.acq_time)
                T.Date(iSes) = Scans.acq_time(1);
                if ~T.Meg(iSes)
                    % Make sure it's not because there was no sessionLog, if looking in sourcedata folder.
                    if any(contains(Scans.filename, '_meg.ds'))
                        T.Meg(iSes) = true;
                    end
                end
            elseif Verbose
                fprintf('Warning: Empty scans.tsv file: %s\n', T.ScansFile{iSes});
            end
        end
    end
end
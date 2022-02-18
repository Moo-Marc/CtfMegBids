function T = BidsSessions(BidsFolder, Verbose)
    % List sessions from BIDS dataset in table (Subject, Session, Date, ScansFile).
    %
    % SesTable = BidsSessions(BidsFolder, Verbose)
    %
    % Marc Lalancette, 2022-02-07
    
    if nargin < 2 || isempty(Verbose)
        Verbose = true;
    end
    
    % Only looks at first recording in each _scans.tsv file.
    SubSes = dir(fullfile(BidsFolder, 'sub-*', 'ses-*'));
    nSes = size(SubSes, 1);
    T = table('Size', [nSes, 4], 'VariableTypes', {'cellstr', 'cellstr', 'datetime', 'cellstr'}, ...
        'VariableNames', {'Subject', 'Session', 'Date', 'ScansFile'});

    T.Session = replace({SubSes.name}', 'ses-', '');
    T.Subject = replace(replace({SubSes.folder}', [BidsFolder, filesep], ''), 'sub-', '');
    
    % Get session dates.
    for iSes = 1:nSes
        T.ScansFile{iSes} = fullfile(['sub-', T.Subject{iSes}], ['ses-', T.Session{iSes}], ...
            ['sub-', T.Subject{iSes}, '_ses-', T.Session{iSes}, '_scans.tsv']);
        %             T.ScansFile = fullfile(BidsFolder, Subjects{iSes}, Sessions{iSes}, ...
        %                 [Subjects{iSes}, '_', Sessions{iSes}, '_scans.tsv']);
        if ~exist(fullfile(BidsFolder, T.ScansFile{iSes}), 'file')
            if Verbose
                fprintf('Warning: Missing scans.tsv file: %s\n', T.ScansFile{iSes});
            end
        else
            Scans = ReadScans(fullfile(BidsFolder, T.ScansFile{iSes}));
            if ~isempty(Scans.acq_time)
                T.Date(iSes) = Scans.acq_time(1);
            elseif Verbose
                fprintf('Warning: Empty scans.tsv file: %s\n', T.ScansFile{iSes});
            end
        end
    end
end
    function Scans = ReadScans(ScansFile)
        % Read a BIDS _scans.tsv file.
        if exist(ScansFile, 'file')
            % Don't rely on Matlab to recognize datetime, it doesn't accept nanoseconds.
            Scans = readtable(ScansFile, 'FileType', 'text', 'DatetimeType', 'text', ...
                'Delimiter', '\t', 'ReadVariableNames', true);
            Scans.acq_time = StrToDatetime(Scans.acq_time);
        else
            error('ScansFile not found: %s', ScansFile);
        end
    end

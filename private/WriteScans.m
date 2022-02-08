    function WriteScans(Scans, ScansFile)
        % Write a BIDS _scans.tsv file.
        
        % Sort in chronological order, not required but simplifies comparisons.
        Scans = sortrows(Scans, {'acq_time', 'filename'});
        Scans.acq_time = DatetimeToStr(Scans.acq_time);
        writetable(Scans, ScansFile, 'FileType', 'text', 'Delimiter', '\t');
    end

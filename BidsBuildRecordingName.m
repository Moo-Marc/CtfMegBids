function Name = BidsBuildRecordingName(BidsInfo)
    Name = ['sub-', BidsInfo.Subject, '_ses-', BidsInfo.Session, '_task-', BidsInfo.Task];
    if isfield(BidsInfo, 'Acq') && ~isempty(BidsInfo.Acq)
        Name = [Name, '_acq-', BidsInfo.Acq]; %#ok<*AGROW>
    end
    if isfield(BidsInfo, 'Run') && ~isempty(BidsInfo.Run)
        Name = [Name, '_run-', BidsInfo.Run]; % string
    end
    Name = [Name, '_meg.ds'];
end


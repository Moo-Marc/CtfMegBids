function UnknownFiles = BidsMegAnonymize(BidsFolder)
% Anonymize raw CTF MEG recordings.

    RecordingsList = dir(fullfile(BidsFolder, '**', '*.ds'));
%     % Remove hz.ds
%     RecordingsList(strcmpi({RecordingsList.name}, 'hz.ds')) = [];
    nR = numel(RecordingsList);
    UnknownFiles = {};
    for r = 1:nR
        UnknownFiles = [UnknownFiles; ...
            Bids_ctf_rename_ds(fullfile(RecordingsList(r).folder, RecordingsList(r).name), [], [], true)]; %#ok<AGROW>
    end

    disp(UnknownFiles);
    
end
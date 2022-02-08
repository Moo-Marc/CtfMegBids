function BidsSetPath()
    % Set up Matlab path, including some Brainstorm dependencies.
    MPath = fileparts(mfilename('fullpath'));
    %     addpath(MPath);
    if isempty(which('in_channel_pos')) || isempty(which('readCPersist'))
        if isempty(which('brainstorm'))
            addpath(fullfile(MPath, 'BstDependencies'));
        else
            brainstorm('setpath');
        end
    end
    %         addpath('/meg/meg1/software/BIDS');
    %         addpath('/meg/meg1/software/brainstorm3');

    
end
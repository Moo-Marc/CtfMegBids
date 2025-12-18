function J = StructOverwrite(J, NewJ)
    % Does not recurse through levels, only copies first level.
    % See also UpdateStruct function, which is recursive.
    if isempty(NewJ)
        % Nothing to copy.
        return;
    end
    if ~isstruct(J) || ~isstruct(NewJ)
        error('Expecting struct.');
    end
    FieldNames = fieldnames(NewJ);
    for f = 1:numel(FieldNames)
        J.(FieldNames{f}) = NewJ.(FieldNames{f});
    end
end
function S = StructTrim(S)
    % Recursively remove empty fields from multi-level structure.
    for Field = fieldnames(New)'
        Field = Field{1}; %#ok<FXSET>
        if isempty(S.(Field)) % a struct can be empty (e.g. 0x0 but with fields)
            S = rmfield(S, Field);
        elseif isstruct(S.(Field))
            S.(Field) = StructTrim(S.(Field));
            if isempty(S.(Field)) % if the struct was not empty but all its fields were
                S = rmfield(S, Field);
            end
        % else not empty
        end
    end
end

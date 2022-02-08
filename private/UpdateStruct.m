function Old = UpdateStruct(Old, New)
    for Field = fieldnames(New)'
        Field = Field{1}; %#ok<FXSET>
        if isstruct(New.(Field)) && isfield(Old, Field)
            Old.(Field) = UpdateStruct(Old.(Field), New.(Field));
        else
            Old.(Field) = New.(Field);
        end
    end
end

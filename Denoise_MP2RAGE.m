% Define the 4 batches based on their base identifiers and ND status.
% Format: {Base Identifier, isND (true/false), Regularization}
batches = {
    'mp2rage_0p7iso_patientSpecific', false, 60;
    'mp2rage_0p7iso_patientSpecific', true,  5;
    'mp2rage_0p7iso_TrueForm',        false, 60;
    'mp2rage_0p7iso_TrueForm',        true,  5
};

% Get the current working directory (change this if your files are elsewhere)
dataDir = pwd; 

% Loop through each batch configuration
for i = 1:size(batches, 1)
    
    baseName = batches{i, 1};
    isND     = batches{i, 2};
    reg      = batches{i, 3};
    
    % Clear struct to prevent accidental carryover between iterations
    clear MP2RAGE; 
    
    % Construct the wildcard search patterns based on ND status
    if isND
        uni_pattern    = sprintf('%s_UNI_Images_ND_*.nii', baseName);
        inv1_pattern   = sprintf('%s_INV1_ND_*.nii', baseName);
        inv2_pattern   = sprintf('%s_INV2_ND_*.nii', baseName);
        uniden_pattern = sprintf('%s_UNI-DEN_ND_*.nii', baseName); % Target to replace
    else
        uni_pattern    = sprintf('%s_UNI_Images_*.nii', baseName);
        inv1_pattern   = sprintf('%s_INV1_*.nii', baseName);
        inv2_pattern   = sprintf('%s_INV2_*.nii', baseName);
        uniden_pattern = sprintf('%s_UNI-DEN_*.nii', baseName);    % Target to replace
    end
    
    % Find the specific files dynamically
    MP2RAGE.filenameUNI  = get_dynamic_filename(dataDir, uni_pattern, isND);
    MP2RAGE.filenameINV1 = get_dynamic_filename(dataDir, inv1_pattern, isND);
    MP2RAGE.filenameINV2 = get_dynamic_filename(dataDir, inv2_pattern, isND);
    MP2RAGE.filenameOUT  = get_dynamic_filename(dataDir, uniden_pattern, isND);
    
    % Check if all necessary files (including the target to replace) were found
    if isempty(MP2RAGE.filenameUNI) || isempty(MP2RAGE.filenameINV1) || isempty(MP2RAGE.filenameINV2)
        fprintf('Warning: Missing input files for %s (ND=%d). Skipping this batch.\n', baseName, isND);
        continue;
    end
    
    if isempty(MP2RAGE.filenameOUT)
        fprintf('Warning: Could not find existing UNI-DEN file to replace for %s (ND=%d). Skipping.\n', baseName, isND);
        continue;
    end
    
    fprintf('Processing: %s (Regularization: %d)\n', MP2RAGE.filenameUNI, reg);
    fprintf('Overwriting existing file: %s\n', MP2RAGE.filenameOUT);
    
    % Run the robust combination (this will overwrite the existing UNI-DEN file)
    [MP2RAGEimgRobustPhaseSensitive] = RobustCombination(MP2RAGE, reg);
    
end

fprintf('All available batches processed successfully.\n');

% -------------------------------------------------------------------------
% LOCAL HELPER FUNCTION
% -------------------------------------------------------------------------
function fname = get_dynamic_filename(dir_path, pattern, isND)
    % Search for files matching the wildcard pattern
    files = dir(fullfile(dir_path, pattern));
    
    % If we are searching for NON-ND files, filter out any matches 
    % that accidentally contain '_ND_' in their name
    if ~isND && ~isempty(files)
        keep_idx = ~contains({files.name}, '_ND_');
        files = files(keep_idx);
    end
    
    % Return the string of the filename, or empty if nothing found
    if isempty(files)
        fname = '';
    else
        fname = files(1).name; % Grabs the first match
    end
end
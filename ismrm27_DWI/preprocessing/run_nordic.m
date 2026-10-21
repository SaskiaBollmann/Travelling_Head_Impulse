function run_nordic(varargin)
	% RUN_NORDIC Execute NORDIC denoising on magnitude and phase DWI NIFTI images
	% ---------------------------------------------------------------------------
	%
    % Version:  0.7.0
    % Author:   Daniel Uher
    % E-mail:   daniel.uher@ovgu.de
    %
    % Most recent logs:
    % MayJun-2026 
    % - named inputs are now utilized, see the documentation below for the
    % argument names
    % - save noise map is possible now
    % - rewrite of the input structure towards named kwargs
    % - plot results migrated to a separate function 'plot_nordic_results.m'
    % 15-Apr-2026 added option to save the noise map and the residual
    % 26-Nov-2025 added versioning and fix 
    %
	% USAGE:
	%   run_nordic(full_path_nii_mag, full_path_nii_pha, full_path_bvals, output_directory, output_name, numThreads, plot_results, save_noise_map, save_residual)
	%
	% DESCRIPTION:
	%   Performs NORDIC (NOise Reduction with DIstribution Corrected) denoising
	%   on diffusion MRI data using both magnitude and phase iamges. This
	%   function configures default NORDIC parameters and executes the pipeline
	%
	% INPUTS:
	%   mag             - REQUIRED - [default '']    String, full path to magnitude .nii file
	%   pha             - REQUIRED - [default '']    String, full path to phase .nii file
	%   outdir          - REQUIRED - [default '']    String, directory path for output files (MUST END WITH '/'!! For instance, '/path/to/output/dir/' ) P.S. the slash might be reversed on Windows, please check
	%   outname         - REQUIRED - [default '']    String, base name for output files (without the '.nii' file extension)
	%
    %   threads         - optional - [default 1]     Numeric, number of computational threads to use
	%   save_plot       - optional - [default false] String, 'yes' or 'no'. Controls whether to create a .png overview of the denoising results
    %   bvals           - optional - [default '']    String, full path to .bval file, only necessary if save_plot=true
    %   save_noise      - optional - [default true]  String, 'yes' or 'no'. Saves the estimated 3D noise map.
	%
	% OUTPUTS:
	%   - Denoised <output_directory><output_name>.nii file written to output_directory with output_name prefix
	%	- <output_directory><output_name>_overview.png denoising results overview for each b-shell (only if save_plot==true)
	%
	% DEPENDENCIES:
	%   - NIFTI_tools package for NIFTI file handling (downloadable here: https://www.mathworks.com/matlabcentral/fileexchange/8797-tools-for-nifti-and-analyze-image)
	%   - NORDIC_Raw package for NORDIC denoising implementation (downloadable here: https://github.com/SteenMoeller/NORDIC_Raw)
	%
	% EXAMPLE:
    %   run_nordic( mag='/path/to/magnitude.nii', ...
    %               pha='/path/to/phase.nii', ...
    %               outdir='/path/to/output_directory/', ...
    %               outname='sub-xx_proc-nordic', ...
    %               threads=8, ...
    %               save_noise=true, ...
    %               save_plot=true, ...
    %               bvals='/path/to/file.bval');
    %
    %   or for older versions of MATLAB in case the above does not work
    %
    %   run_nordic( 'mag', '/path/to/magnitude.nii', ...
    %               'pha', '/path/to/phase.nii', ...
    %               'outdir', '/home/duher/test_data', ...
    %               'outname', 'sub-07_desc-run-nordic-test-nii', ...
    %               'threads', 8, ...
    %               'save_noise', true, ...
    %               'save_plot', true, ...
    %               'bvals', '/path/to/file.bval');
	%
	% ---------------------------------------------------------------------------
	
				
	% ------------------------------------------------------------------------------	
	% PLEASE ADAPT THE PATHS TO THE TOOLBOXES BEFORE EXECUTION
	% ------------------------------------------------------------------------------
	
	% Specify path to NIFTI tools
	addpath(genpath('/home/duher/Tools/matlab/NIFTI_tools'));
	
	% Specify path to NORDIC
	addpath(genpath('/home/duher/Tools/matlab/NORDIC_Raw-main'));

    % Specify path to MRtrix MATLAB functions
    % NORDIC is dependent internally on the niftiinfo structure which
    % and therefore usage of .mif is discouraged. For general citation 
    % purposes, it is better to use .nii and then simply cite that 'we 
    % used NORDIC for denoising from their github'. But, if you want to 
    % play around with this, you can uncomment and fill in the path below.
    % To run NORDIC on .mif, you need to inject the read_mrtrix into
    % the NIFTI_NORDIC script itself and carefully match what NIFTI_NORDIC
    % takes from the niftiinfo to what read_mrtrix parses for you.
    % The MRtrix matlab functions are stored at the Z02 github at
	% addpath(genpath('/home/duher/Documents/MATLAB'));

	% ---------------------------------------------------------------------	
	
	
    % =====================================================================
	% EDITING BELOW THIS POINT IS NOT REQUIRED
    % =====================================================================

    % =====================================================================
    % parse arguments
    % =====================================================================
    p = inputParser;
    p.FunctionName = 'run_nordic';
    addParameter(p, 'mag',          '',                      @ischar);                        % full path to magnitude .nii/.mif 
    addParameter(p, 'pha',          '',                      @ischar);                        % full path to phase     .nii/.mif, 
    addParameter(p, 'outdir',       '',                      @ischar);                        % output directory, 
    addParameter(p, 'outname',      'sub-00_proc-nordic',    @ischar);                        % output name, 
    addParameter(p, 'threads',      '1',                     @(x) (ischar(x) && ~isempty(str2double(x))) || (isnumeric(x) && isscalar(x) && x > 0));     % number of threads to be used, 
    addParameter(p, 'save_noise',   true,                    @islogical);                     % save noise map, 
    addParameter(p, 'save_plot',    false,                   @islogical);
    addParameter(p, 'bvals',        '',                      @ischar); % full path to .bval
    parse(p, varargin{:});
    disp(p.Results);

    full_path_nii_mag = p.Results.mag;
    full_path_nii_pha = p.Results.pha;
    output_directory  = p.Results.outdir;
    output_name       = p.Results.outname;
    numThreads        = p.Results.threads;
    save_noise_map    = p.Results.save_noise;
    save_plot         = p.Results.save_plot;
    full_path_bvals   = p.Results.bvals;

	% =====================================================================
    % Input path validation
    % =====================================================================
	disp("Validating inputs...");
	
	% Check if tool paths were added correctly
	fullfile_path = which('NIFTI_NORDIC');
	if isempty(fullfile_path)
		error('NIFTI_NORDIC is not reachable. Please double-check that you added the NORDIC_Raw toolbox to the path. Downloadable here: https://github.com/SteenMoeller/NORDIC_Raw');
	end
	
	fullfile_path = which('load_untouch_nii');
	if isempty(fullfile_path)
		error('NIFTI_tools is not reachable. Please double-check that you added the nifti_tools toolbox to the path. Downloadable here: https://www.mathworks.com/matlabcentral/fileexchange/8797-tools-for-nifti-and-analyze-image');
    end

    fullfile_path = which('read_mrtrix');
	if isempty(fullfile_path)
		warning('MRtrix MATLAB functions are not reachable. Please double-check that you added all the MRtrix MATLAB tools to the specified path. You can clone the MRtrix repository and copy out the _matlab_ folder: https://github.com/MRtrix3/mrtrix3/tree/master');
	end
	
	% Check if magnitude file exists
	if ~isfile(full_path_nii_mag)
		error('Magnitude file does not exist: %s', full_path_nii_mag);
	else
		fprintf("PASS    Magnitude image:   %s\n", full_path_nii_mag);
	end
	
	% Check if phase file exists
	if ~isfile(full_path_nii_pha)
		error('Phase file does not exist: %s', full_path_nii_pha);
	else
		fprintf("PASS    Phase image:   %s\n", full_path_nii_pha);
    end
	
	% Check if output directory exists, create if not
	if ~isfolder(output_directory)
		warning('Output directory does not exist. Creating: %s', output_directory);
		mkdir(output_directory);
	else
		fprintf("PASS    output dir:   %s\n", output_directory)
	end
	
	% Check if output directory ends with a file separator, add if not
	if ~isempty(output_directory) && (output_directory(end) == '/' || output_directory(end) == '\')
        disp('PASS    String correctly ends with path separator')
	else
		output_directory = [output_directory filesep];
		disp(['Added file separator to the output_directory. Result: ' output_directory])
		disp(['File separator used: ' filesep])
	end

	% Check for mixed separators in all cases
	if contains(output_directory, '/') && contains(output_directory, '\')
		disp('WARNING: Path contains mixed separators (/ and \). Consider normalizing with fullfile() or manually edit.')
    end

    if save_plot
        if ~isfile(full_path_bvals) || isempty(full_path_bvals)
            error('For plotting, you need to specify bvals=/path/to/xxx.bval file.')
        end
    end

    % =====================================================================
    % Image load and validation
    % =====================================================================
    
	% Load NIfTI headers to check dimensions
	disp("Checking image dimensions...");
	[~, mag_nii] = load_imdata(full_path_nii_mag);
	[~, pha_nii] = load_imdata(full_path_nii_pha);
	
	% Check if images are 4D (required for NORDIC)
	if ndims(mag_nii) ~= 4
		error('Input images must be 4D (x, y, z, time). Current dimensions: %s', ...
			  mat2str(size(mag_nii)));
	else
		disp("PASS    data is 4-dimensional")
	end
	
	% Check if dimensions between magnitude and phase match
	if ~isequal(size(mag_nii), size(pha_nii))
		error('Magnitude and phase images have different dimensions.\nMag: %s\nPha: %s', ...
			  mat2str(size(mag_nii)), mat2str(size(pha_nii)));
	else
		fprintf("PASS    data dimension match:   %d\n", size(mag_nii))
	end
	
	% Clean up before execution to save memory
	clear mag_nii;
	clear pha_nii;
	
	% Validate number of threads
    if ischar(numThreads)
        numThreads = str2double(numThreads);
    end
	if numThreads < 1
		fprintf('WARNING: Invalid number of threads (%d). Setting to single thread.\n\n', ...                
				numThreads);
		maxNumCompThreads(1);
    else
        maxNumCompThreads(numThreads);
	end
	
	disp("All validation checks passed!");
	disp("-------------------------------------------------------")
	disp('')
	
	disp("============== NORDIC Parameters ==============");
    % set NORDIC internal parameters
    ARG.temporal_phase=3;
	ARG.phase_filter_width=3;
	ARG.DIROUT=output_directory;
    if save_noise_map
        ARG.save_add_info=1;
    end

    % print user-specified inputs
	fprintf("Mag:        %s\n", full_path_nii_mag);
	fprintf("Pha:        %s\n", full_path_nii_pha);
	fprintf("Outname:    %s\n", output_name);
	fprintf("Outdir:     %s\n", output_directory);
	fprintf("numThreads: %s\n", num2str(maxNumCompThreads()));
    disp('')
    disp("===============================================");

    % run nordic
	NIFTI_NORDIC(full_path_nii_mag, full_path_nii_pha, output_name, ARG);

    % saving noise
    if save_noise_map
        disp('Saving noise map ...');
        load(fullfile(output_directory, [output_name '.mat']), 'ARG2');
        
        % get the noise map
        noiseMap = single(ARG2.NOISE);
        noiseMap(isnan(noiseMap)) = 0;
        noiseMap(isinf(noiseMap)) = 0;

        % load header from original input to get voxel size
        refNii = niftiinfo(full_path_nii_mag);
        voxelSize = refNii.PixelDimensions(1:3);

        % build a clean nii struct and save
        nii = make_nii(noiseMap, voxelSize);
        save_nii(nii, fullfile(output_directory, [output_name, '_noise.nii'] ) );
        
    elseif strcmp(save_noise_map, 'no')
        disp('Skipping saving noise map on request.');
    else
        disp('Skipping saving noise map due to invalid save_noise_map specification. Options are -yes- or -no-');
    end   

    if save_plot
        plot_results(full_path_nii_mag, full_path_bvals, output_directory, output_name)
    elseif ~save_plot
        disp('Skipping plotting upon request.')
	else
		disp("Skipping plotting due to invalid plot_results specification. Options are -true- or -false- as boolean, not string");
	end

    disp("============== NORDIC FINISHED ==============");

end


% =========================================================================
% Helper Functions
% =========================================================================

function [hdr, img] = load_imdata(fullpath)
% CHECK_FILE_EXT - Load an image based on its file extension.
% -------------------------------------------------------------------------
%
% img = check_file_ext(fullpath)
%
% Inputs:
%   fullpath .. full path to the image file (string or char)
% Outputs:
%   hdr ....... header information (NOTE: differs between formats!!)
%   img ....... loaded image data (format depends on file type)

    % Handle .nii.gz compound extension
    [~, fname, fext] = fileparts(fullpath);
    if strcmpi(fext, '.gz')
        [~, ~, inner_ext] = fileparts(fname);
        if strcmpi(inner_ext, '.nii')
            fext = '.nii.gz';
        end
    end

    % load the data accordingly
    switch lower(fext)
        case '.nii'
            hdr = niftiinfo(fullpath);
            img = niftiread(fullpath);

        case '.nii.gz'
            hdr = niftiinfo(fullpath);
            img = niftiread(fullpath);

        case '.mif'
            mif = read_mrtrix(fullpath);
            img = int16(mif.data); % read_mrtrix loads into double

            % the read_mrtrix does this flip by default to account for the
            % desired orientation. In order to undo it without modifying
            % the MRtrix original script, I undo it here, but it is not
            % optimal since the axis flipping is then done twice, once
            % during read_mrtrix (do) and then here (undo)
            orientations = split(mif.layout, ',');
            for i = 1:length(mif.dim)
                if orientations{i}(1) == '-'
                    img = flip(img, i);
                end
            end

            % remove the data field from the header to save memory
            hdr = rmfield(mif, 'data');

            warndlg('Format .mif is currently unsupported with NORDIC. The source code of NORDIC itself is dependent on the structure provided by niftiread and niftiinfo only. We cannot change this without substantially rewriting the NORDIC original code which I want to avoid for citation purposes. It might be possible in the future, but now NORDIC will error out because of some nifti error.')

        otherwise
            error('load_imdata: unrecognized extension "%s" for file:\n  %s', fext, fname);
    
    end
end

function plot_results(full_path_nii_mag, full_path_bvals, output_directory, output_name)
    % PLOT_RESULTS plot results after denoising
    % ---------------------------------------------------------------------
    % KNOWN ISSUES:
    % 1. scaling of the axes is very unpretty... working on it.

    
	disp("Plotting the results ...")

    % get the path to the denoised nifti
	denoised_path = [output_directory output_name '.nii'];
	
	% Load .nii data
	mag = niftiread(full_path_nii_mag);
	den = niftiread(denoised_path);
	
    % estimate middle axial slice
	axial_slice = round(size(mag, 3) / 2);

    % check whether the denoised data and original data are the same
    % size. This should be arbitrary but hopefully some unintended
    % naming mishappening
	[X, Y, Z, T] = size(mag);
	assert(all(size(den) == [X, Y, Z, T]), 'Original and denoised data must have same size.');

	% Load b-values from .bval file
    if isempty(full_path_bvals)
        warning('no .bval provided, plotting only first volume')
    else
	    bval_txt = fileread(full_path_bvals);
	    bvals = sscanf(bval_txt, '%f');
    end

    % check if number of bvalues matches the number of volumes
	if length(bvals) ~= T
		error('Number of b-values (%d) does not match number of volumes (%d)', length(bvals), T);
	end

    % get unique b-values and the number of volumes within each b-value
	unique_b = unique(bvals, 'stable');  % Preserves order
	M = numel(unique_b);

	% Preallocate arrays for the original slices and the denoised slices
	mag_slices = zeros(X, Y, M, 'like', mag);
	den_slices = zeros(X, Y, M, 'like', mag);

	% Extract representative axial slice for each b-value and calculate their brightness/contrast windowing
	pmins = [];
	pmaxs = [];

    % for each b-value
	for m = 1:M
		idxs = find(bvals == unique_b(m));

        % get indices of the given b-value volumes
		sel_idx = idxs(randi(numel(idxs)));

        % extract the given volumes and keep only the axial slices
		mag_slices(:, :, m) = squeeze(mag(:, :, axial_slice, sel_idx));
		den_slices(:, :, m) = squeeze(den(:, :, axial_slice, sel_idx));
		
        % estimate contrast/brightness limits for equal windowing from
        % the original data slices
		flatslice = mag_slices(:, :, m);
		flatslice = flatslice(:);
		pmins = [pmins prctile(flatslice, 0.5)];
		pmaxs = [pmaxs prctile(flatslice, 99.5)];
	end

	% Create figure
	fig = figure('Name', 'NORDIC results: Axial Slices by b-value', 'Color', 'w', 'Visible', 'off');
	
	% Calculate subplot positions with minimal margins
	margin_left = 0.02;
	margin_right = 0.02;
	margin_bottom = 0.05;
	margin_top = 0.1;
	gap_horizontal = 0.02;
	gap_vertical = 0.02;
	
    % a very convoluted way to hopefully make sure the subplots fit
    % nicely without wasting too much space (thanks Claude!)
	subplot_width = (1 - margin_left - margin_right - (M-1)*gap_horizontal) / M;
	subplot_height = (1 - margin_bottom - margin_top - gap_vertical) / 2;
	
    % for each b-value
	for m = 1:M

		% Calculate position for original data (top row)
		pos_left = margin_left + (m-1)*(subplot_width + gap_horizontal);
		pos_bottom_top = margin_bottom + subplot_height + gap_vertical;
		
		% Original image m-th b-value subplot (top row)
		ax1 = subplot(2, M, m);

        % show the image and apply the estimated windowing
		imagesc(mag_slices(:, :, m), [pmins(m), pmaxs(m)]); 

        % prettify
		axis image off;
		colormap(ax1, gray);
		title(sprintf('b = %g', unique_b(m)));
		set(ax1, 'Position', [pos_left, pos_bottom_top, subplot_width, subplot_height]);
		

		% Denoised image m-th b-value subplot (bottom row) (same
        % approach)
		pos_bottom_bottom = margin_bottom;
		ax2 = subplot(2, M, M + m);
		imagesc(den_slices(:, :, m), [pmins(m), pmaxs(m)]);
		axis image off;
		colormap(ax2, gray);
		set(ax2, 'Position', [pos_left, pos_bottom_bottom, subplot_width, subplot_height]);
	end
	
	% Add overall title
	title('Axial Slices by b-value (Top: Original, Bottom: NORDIC denoised)');
	
	% Save figure as .png
	exportgraphics(gcf, [output_directory output_name '_overview.png'],'Resolution',300)
	fprintf('Figure saved to: %s\n', [output_directory output_name '_overview.png']);
		
	
end

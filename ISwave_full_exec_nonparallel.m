function ISwave_struct = ISwave_full_exec_nonparallel(symstructs, startFreq, endFreq, Freq_points, deltaV, BC, sequential, frozen_ions, do_graphics, save_solutions, save_results)
%ISWAVE_FULL_EXEC_NONPARALLEL - Do Impedance Spectroscopy approximated applying an
% oscillating voltage (ISwave) in a range of background light intensities.
% Getting rid of annoying parfor
%
% Syntax:  ISwave_struct = ISwave_full_exec_nonparallel(symstructs, startFreq, endFreq, Freq_points, deltaV, BC, sequential, frozen_ions, do_graphics, save_solutions, save_results)
%
% Inputs:
%   SYMSTRUCTS - can be a cell structure containing structs at various background
%     light intensities. This can be generated using genIntStructs.
%     Otherwise it can be a single struct as created by PINDRIFT.
%   STARTFREQ - higher frequency limit
%   ENDFREQ - lower frequency limit
%   FREQ_POINTS - number of points to simulate between STARTFREQ and
%     ENDFREQ
%   DELTAV - voltage oscillation amplitude in volts, one mV should be enough
%   BC - boundary conditions indicating if the contacts are selective, see
%     PINDRIFT
%   SEQUENTIAL - logical, if true do not check that the oscillating solution reached a
%     (oscillating) stabilization, instead take always the first solution
%     and use its final timepoint as the starting point of the next
%     frequency simulation. This can be useful when it's known that the
%     starting solution is not stabilized and a realistic simulation of the
%     solution evolving during the measurement is wanted.
%   FROZEN_IONS - logical, after stabilization sets the mobility of
%     ionic defects to zero
%   DO_GRAPHICS - logical, whether to graph the individual solutions and
%     the overall graphics
%   SAVE_SOLUTIONS - is a logic defining if to assing in volatile base
%     workspace the calulated solutions of single ISstep perturbations
%   SAVE_RESULTS - is a logic defining if to assing in volatile base
%     workspace the most important results of the simulation
%
% Outputs:
%   ISWAVE_STRUCT - a struct containing the most important results of the simulation
%
% Example:
%   ISwave_full_exec_nonparallel(genIntStructs(ssol_i_eq, ssol_i_light, 100, 1e-7, 4), 1e9, 1e-2, 23, 1e-3, 1, true, false, true, true, true)
%     calculate also with dark background, do not freeze ions, use a
%     voltage oscillation amplitude of 1 mV, on 23 points from frequencies of 1 GHz to
%     0.01 Hz, with selective contacts, without calculating ionic current,
%     without parallelization
%   ISwave_full_exec_nonparallel(genIntStructs(ssol_i_eq, ssol_i_light, 100, 1e-7, 4), 1e9, 1e-2, 23, 1e-3, 1, true, true, true, true, true)
%     as above but freezing ions during voltage oscillation
%   ISwave_full_exec_nonparallel(ssol_i_light_BC2, 1e9, 1e-2, 23, 1e-3, 2, true, false, true, true, true)
%     use non perfectly selective contacts (BC = 2)
%
% Other m-files required: asymmetricize, ISwave_single_exec,
%   ISwave_single_analysis, ISwave_full_analysis_nyquist,
%   IS_full_analysis_vsfrequency
% Subfunctions: none
% MAT-files required: none
%
% See also genIntStructs, pindrift, ISwave_single_exec, ISwave_full_analysis_nyquist, ISwave_single_analysis.

% Author: Ilario Gelmetti, Ph.D. student, perovskite photovoltaics
% Institute of Chemical Research of Catalonia (ICIQ)
% Research Group Prof. Emilio Palomares
% email address: iochesonome@gmail.com
% Supervised by: Dr. Phil Calado, Dr. Piers Barnes, Prof. Jenny Nelson
% Imperial College London
% October 2017; Last revision: January 2018

%------------- BEGIN CODE --------------

% in case a single struct is given in input, convert it to a cell structure
% with just one cell
if length(symstructs(:, 1)) == 1 % if the input is a single structure instead of a cell with structures
    symstructs_temp = cell(2, 1);
    symstructs_temp{1, 1} = symstructs;
    symstructs_temp{2, 1} = inputname(1);
    symstructs = symstructs_temp;
end

% don't display figures until the end of the script, as they steal the focus
% taken from https://stackoverflow.com/questions/8488758/inhibit-matlab-window-focus-stealing
if do_graphics
    set(0, 'DefaultFigureVisible', 'off');
end

% which method to use for extracting phase and amplitude of the current
% if false, always uses fitting, if true uses demodulation multiplying the current
% by sin waves. Anyway if the obtained phase is werid, fit will be used
demodulation = true;

% number of complete oscillation periods to simulate
% the current looks reproducible already after few oscillations, this could be set in an automatic way
% this number should be above 20 for having good phase estimation in dark
% solutions via ISwave_single_demodulation
periods = 20;

% for having a meaningful output from verifyStabilization, here use a
% number of tpoints which is 1 + a multiple of 4 * periods
tpoints_per_period = 10 * 4; % gets redefined by changeLight, so re-setting is needed

% default pdepe tolerance is 1e-3, for having an accurate phase from the
% fitting, improving the tollerance is useful
RelTol = 1e-6;

% define frequency values
Freq_array = logspace(log10(startFreq), log10(endFreq), Freq_points);

%% pre allocate arrays filling them with zeros
Vdc_array = zeros(length(symstructs(1, :)), 1);
Int_array = Vdc_array;
tmax_matrix = zeros(length(symstructs(1, :)), length(Freq_array));
J_bias = tmax_matrix;
J_amp = tmax_matrix;
J_phase = tmax_matrix;
J_i_bias = tmax_matrix;
J_i_amp = tmax_matrix;
J_i_phase = tmax_matrix;

%% do a serie of IS measurements

disp([mfilename ' - Doing the IS at various light intensities']);
for i = 1:length(symstructs(1, :))
    struct = symstructs{1, i};
    Int_array(i) = struct.p.Int;
    % decrease annoiance by figures popping up
    struct.p.figson = 0;
    if struct.p.OC % in case the solution is symmetric, break it in halves
        [asymstruct_Int, Vdc_array(i)] = asymmetricize(struct, BC); % normal BC 1 should work, also BC 2 can be employed
    else
        asymstruct_Int = struct;
        Vdc_array(i) = struct.Efn(end) - struct.Efp(1);
    end
    if frozen_ions
        asymstruct_Int.p.mui = 0; % if frozen_ions option is set, freezing ions
    end
    % simulate first frequency with the stabilized solution
    asymstruct_start = asymstruct_Int;
    for (j = 1:length(Freq_array))
        tempRelTol = RelTol; % reset RelTol variable
        asymstruct_ISwave = ISwave_single_exec(asymstruct_start, BC, deltaV,...
            Freq_array(j), periods, tpoints_per_period, ~sequential, false, tempRelTol); % do IS
        % set ISwave_single_analysis minimal_mode to true if parallelize is
        % true or if do_graphics is false
        % extract parameters and do plot
        [fit_coeff, fit_idrift_coeff, ~, ~, ~, ~, ~, ~] = ISwave_single_analysis(asymstruct_ISwave, ~do_graphics, demodulation);
        % if phase is small or negative, double check increasing accuracy of the solver
        % a phase close to 90 degrees can be indicated as it was -90 degree
        % by the demodulation, the fitting way does not have this problem
        if fit_coeff(3) < 0.006 || fit_coeff(3) > pi/2 - 0.006
            disp([mfilename ' - Freq: ' num2str(Freq_array(j)) '; Fitted phase is ' num2str(rad2deg(fit_coeff(3))) ' degrees, it is extremely small or close to pi/2 or out of 0-pi/2 range, increasing solver accuracy and calculate again'])
            tempRelTol = tempRelTol / 100;
            % if just the initial solution, non-stabilized, is requested, do
            % not start from oscillating solution
            if sequential
                asymstruct_temp = asymstruct_start; % strictly use the last point from previous cycle
            else
                asymstruct_temp = asymstruct_ISwave; % the oscillating solution, better starting point
            end
            asymstruct_ISwave = ISwave_single_exec(asymstruct_temp, BC,...
                deltaV, Freq_array(j), periods, tpoints_per_period, ~sequential, false, tempRelTol); % do IS
            % set ISwave_single_analysis minimal_mode is true if parallelize is true
            % repeat analysis on new solution
            [fit_coeff, fit_idrift_coeff, ~, ~, ~, ~, ~, ~] = ISwave_single_analysis(asymstruct_ISwave, ~do_graphics, demodulation);
        end
        % if phase is still negative or bigger than pi/2, likely is demodulation that is
        % failing (no idea why), use safer fitting method without repeating
        % the simulation
        if fit_coeff(3) < 0 || fit_coeff(3) > pi/2
            disp([mfilename ' - Freq: ' num2str(Freq_array(j)) '; Phase from demodulation is weird: ' num2str(rad2deg(fit_coeff(3))) ' degrees, confirming using fitting'])
            % use fitting
            [fit_coeff, fit_idrift_coeff, ~, ~, ~, ~, ~, ~] = ISwave_single_analysis(asymstruct_ISwave, ~do_graphics, false);
            disp([mfilename ' - Freq: ' num2str(Freq_array(j)) '; Phase from fitting is: ' num2str(rad2deg(fit_coeff(3))) ' degrees'])
        end
        % if phase is still negative or more than pi/2, check again increasing accuracy
        if fit_coeff(3) < 0 || abs(fit_coeff(3)) > pi/2
            disp([mfilename ' - Freq: ' num2str(Freq_array(j)) '; Fitted phase is ' num2str(rad2deg(fit_coeff(3))) ' degrees, it is out of 0-pi/2 range, increasing solver accuracy and calculate again'])
            tempRelTol = tempRelTol / 100;
            % if just the initial solution, non-stabilized, is requested, do
            % not start from oscillating solution
            if sequential
                asymstruct_temp = asymstruct_start; % strictly use the last point from previous cycle
            else
                asymstruct_temp = asymstruct_ISwave; % the oscillating solution, better starting point
            end
            asymstruct_ISwave = ISwave_single_exec(asymstruct_temp, BC,...
                deltaV, Freq_array(j), periods, tpoints_per_period, ~sequential, false, tempRelTol); % do IS
            % set ISwave_single_analysis minimal_mode is true if parallelize is true
            % repeat analysis on new solution
            % use fitting
            [fit_coeff, fit_idrift_coeff, ~, ~, ~, ~, ~, ~] = ISwave_single_analysis(asymstruct_ISwave, ~do_graphics, false);
        end
        J_bias(i, j) = fit_coeff(1); % not really that useful
        J_amp(i, j) = fit_coeff(2);
        J_phase(i, j) = fit_coeff(3);
        J_i_bias(i, j) = fit_idrift_coeff(1);
        J_i_amp(i, j) = fit_idrift_coeff(2);
        J_i_phase(i, j) = fit_idrift_coeff(3);

        % as the number of periods is fixed, there's no need for tmax to be
        % a matrix, but this could change, so it's a matrix
        tmax_matrix(i,j) = asymstruct_ISwave.p.tmax;
        
        if save_solutions % assignin cannot be used in a parallel loop, so single solutions cannot be saved
            sol_name = matlab.lang.makeValidName([symstructs{2, i} '_Freq_' num2str(Freq_array(j)) '_ISwave']);
            asymstruct_ISwave.p.figson = 1; % re-enable figures by default when using the saved solution, that were disabled above
            assignin('base', sol_name, asymstruct_ISwave);
        end
        % in case the next simulation is run starting from the last time
        % point of this simulation, redefine the starting point
        % otherwise the originally provided solution is used again
        if sequential
            asymstruct_start = asymstruct_ISwave;
        end
    end
end

%% calculate apparent capacity 

sun_index = find(Int_array == 1); % could used for plotting... maybe...

% even if here the frequency is always the same for each illumination, it
% is not the case for ISstep, and the solution has to be more similar in
% order to be used by the same IS_full_analysis_vsfrequency script
Freq_matrix = repmat(Freq_array, length(symstructs(1, :)), 1);

% deltaV is a scalar, J_amp and J_phase are matrices
% as the current of MPP is defined as positive in the model, we expect that
% with a positive deltaV we have a negative J_amp (J_amp is forced to be negative actually)

% the absolute value of impedance has to be taken from the absolute values
% of oscillation of voltage and of current
impedance_abs = -deltaV ./ J_amp; % J_amp is in amperes
% the components of the impedance gets calculated with the phase from the
% current-voltage "delay"
impedance_re = impedance_abs .* cos(J_phase); % this is the resistance
impedance_im = impedance_abs .* sin(J_phase);
pulsatance_matrix = 2 * pi * repmat(Freq_array, length(symstructs(1, :)), 1);
% the capacitance is the imaginary part of 1/(pulsatance*complex_impedance)
% or can be obtained in the same way with Joutphase/(pulsatance*deltaV)
cap = sin(J_phase) ./ (pulsatance_matrix .* impedance_abs);

impedance_i_abs = -deltaV ./ J_i_amp; % J_amp is in amperes
impedance_i_re = impedance_i_abs .* cos(J_i_phase); % this is the resistance
impedance_i_im = impedance_i_abs .* sin(J_i_phase);
cap_idrift = sin(J_i_phase) ./ (pulsatance_matrix .* impedance_i_abs);

%% save results

% this struct is similar to ISstep_struct in terms of fields,
% but the columns and rows in the fields can be different
ISwave_struct.sol_name = symstructs{2, 1};
ISwave_struct.Vdc = Vdc_array;
ISwave_struct.periods = periods;
ISwave_struct.Freq = Freq_matrix;
ISwave_struct.tpoints = 1 + tpoints_per_period * periods;
ISwave_struct.tmax = tmax_matrix;
ISwave_struct.Int = Int_array;
ISwave_struct.BC = BC;
ISwave_struct.deltaV = deltaV;
ISwave_struct.sun_index = sun_index;
ISwave_struct.J_bias = J_bias;
ISwave_struct.J_amp = J_amp;
ISwave_struct.J_phase = J_phase;
ISwave_struct.J_i_bias = J_i_bias;
ISwave_struct.J_i_amp = J_i_amp;
ISwave_struct.J_i_phase = J_i_phase;
ISwave_struct.cap = cap;
ISwave_struct.impedance_abs = impedance_abs;
ISwave_struct.impedance_im = impedance_im;
ISwave_struct.impedance_re = impedance_re;
ISwave_struct.cap_idrift = cap_idrift;
ISwave_struct.impedance_i_abs = impedance_i_abs;
ISwave_struct.impedance_i_im = impedance_i_im;
ISwave_struct.impedance_i_re = impedance_i_re;
if save_results
    assignin('base', ['ISwave_' symstructs{2, 1}], ISwave_struct);
end

%% plot results

if do_graphics
    ISwave_EA_full_analysis_phase(ISwave_struct);
    IS_full_analysis_impedance(ISwave_struct);
    ISwave_full_analysis_nyquist(ISwave_struct);

    % make the figures appear, all at the end of the script
    set(0, 'DefaultFigureVisible', 'on');
    figHandles = findall(groot, 'Type', 'figure');
    set(figHandles(:), 'visible', 'on')
end

%------------- END OF CODE --------------
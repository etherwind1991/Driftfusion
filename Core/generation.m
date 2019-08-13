function gx = generation(par, source_type, laserlambda)
% This function calls the correct funciton to calculate generation profiles as a function of position
% SOURCE_TYPE = either 'AM15' or 'laser'
% LASERLAMBDA = Laser wavelength - ignored if SOURCE_TYPE = AM15

xsolver = getvarihalf(par.xx);
switch par.OM
    case 0
        gx = getvarihalf(par.dev.g0);    % This currently results in the generation profile being stored twice and could be optimised
    case 1
        % beerlambert(par, x, source_type, laserlambda, figson)
        gx = beerlambert(par, par.xx, source_type, laserlambda, 0);
        % Remove interfaces
        for i = 1:length(par.layer_type)
            if strcmp(par.layer_type{1,i}, 'junction') == 1
                gx(par.pcum0(i):par.pcum0(i+1)) = 0;
            end
        end
        
        % interpolate for i+0.5 mesh
        gx = interp1(par.xx, gx, xsolver);  

%     case 2
%         par.genspace = x(x > par.dcum(1) & x < par.dcum(2));    % Active layer points for interpolation- this could all be implemented better but ea
%         
%         %% TRANSFER MATRIX NOT CURRENTLY AVAILABLE
%         % Call Transfer Matrix code: [Gx1, Gx2] = TMPC1(layers, thicknesses, activeLayer1, activeLayer2)
%         [Gx1S, GxLas] = TMPC1({'TiO2' 'MAPICl' 'Spiro'}, [par.d(1)+0.5*par.dint, par.d(2)+0.5*par.dint, par.d(3)+0.5*par.dint], 2, 2, par.laserlambda, par.pulsepow);
%         Gx1S = Gx1S';
%         GxLas = GxLas';  
end

end
classdef (Abstract) mlapptools
    % MLAPPTOOLS A collection of static methods for customizing various aspects
    % MATLAB App Designer UIFigures.
    %
    % MLAPPTOOLS methods:
    % textAlign  - utility method for modifying text alignment.
    % fontWeight - utility method for modifying font weight (bold etc.).
    % fontColor  - utility method for modifying font color.
    % setStyle   - utility method for modifying styles that do not (yet) have a
    %              dedicated mutator.
    % aboutDojo  - returns version information about the Dojo toolkit.
    
    properties (Access = private, Constant = true)
        QUERY_TIMEOUT = 5;  % Dojo query timeout period, seconds
    end
            
    methods (Access = public, Static = true)
        function textAlign(uielement, alignment)
        % A method for manipulating text alignment.
            alignment = lower(alignment);
            mlapptools.validateAlignmentStr(alignment)
            
            [win, widgetID] = mlapptools.getWebElements(uielement);
            
            alignSetStr = sprintf('dojo.style(dojo.query("#%s")[0], "textAlign", "%s")', widgetID, alignment);
            win.executeJS(alignSetStr);
        end % textAlign
        
        
        function fontWeight(uielement, weight)
        % A method for manipulating font weight, which controls how thick or 
        % thin characters in text should be displayed.
            weight = mlapptools.validatefontweight(weight);
            
            [win, widgetID] = mlapptools.getWebElements(uielement);
            
            fontWeightSetStr = sprintf('dojo.style(dojo.query("#%s")[0], "font-weight", "%s")', widgetID, weight);
            win.executeJS(fontWeightSetStr);
        end % fontWeight
        
        
        function fontColor(uielement, newcolor)
        % A method for manipulating text color.
            newcolor = mlapptools.validateCSScolor(newcolor);

            [win, widgetID] = mlapptools.getWebElements(uielement);
            
            fontColorSetStr = sprintf('dojo.style(dojo.query("#%s")[0], "color", "%s")', widgetID, newcolor);
            win.executeJS(fontColorSetStr);
        end % fontColor
        
        function varargout = setStyle(varargin)
        % A method providing an interface for modifying style attributes of uicontrols. 
        %
        % WARNING: Due to the large amount of available style attributes and 
        % corresponding settings, input checking is not performed. As this
        % might lead to unexpected results or errors - USE AT YOUR OWN RISK!
        %
        % "Overloads":
        % 3-parameter call: 
        %   widgetID = setStyle(hControl, styleAttr, styleValue)
        % 4-parameter call: 
        %              setStyle(hUIFig,   styleAttr, styleValue, widgetID)
        
            % Unpack inputs:
            styleAttr = varargin{2};
            styleValue = varargin{3};
            
            switch nargin
              case 3
                hControl = varargin{1};
                % Get a handle to the webwindow
                [win, widgetID] = mlapptools.getWebElements(hControl);
              case 4                
                hUIFig = varargin{1};
                widgetID = varargin{4};

                % Get a handle to the webwindow  
                win = mlapptools.getWebWindow(hUIFig);
            end
                               
            styleSetStr = sprintf('dojo.style(dojo.query("#%s")[0], "%s", "%s")', widgetID, styleAttr, styleValue);
            % ^ this might result in junk if widgetId=='null'.
            try 
              win.executeJS(styleSetStr);
              % ^ this might crash in case of invalid styleAttr/styleValue.
            catch ME
                % Test for "Invalid or unexpected token":
                ME = mlapptools.checkJavascriptSyntaxError(ME, styleSetStr);
                rethrow(ME);       
            end
            
            % Assign outputs:
            if nargout >= 1
              varargout{1} = widgetID;
            end
            
        end % setStyle
                
        function [dojoVersion] = aboutDojo()
        % A method for getting version info about the Dojo Toolkit version visible by MATLAB.
        
            if ~numel(matlab.internal.webwindowmanager.instance.findAllWebwindows())
                f=uifigure; drawnow; tmpWindowCreated = true;              
            else
                tmpWindowCreated = false;
            end

            dojoVersion = matlab.internal.webwindowmanager.instance ...
                                .windowList(1).executeJS('dojo.version');

            if tmpWindowCreated
                delete(f);
            end
            % If MATLAB is sufficiently new, convert the JSON to a struct:  
            if str2double(subsref(ver('matlab'), substruct('.','Version'))) >= 9.1 %R2016b
                dojoVersion = jsondecode(dojoVersion);
            end
        end % aboutDojo
        
        function [fullHTML] = getHTML(hUIFig)
        % A method for dumping the HTML code of a uifigure. 
        % Intended for R2017b (and onward?) where the CEF url cannot be simply opened in a browser.
                
            win = mlapptools.getWebWindow(hUIFig);            
            % Get the outer html:
            fullHTML = win.executeJS('document.documentElement.outerHTML');
            % Replace some strings for conversion to work well:
            fullHTML = strrep(fullHTML,'%','%%');
            fullHTML = strrep(fullHTML,'><','>\n<');
            % Append the DOCTYPE header and remove quotes:
            fullHTML = sprintf(['<!DOCTYPE HTML>\n' fullHTML(2:end-1)]);
            
        %% Optional things to do with the output:
        % Display as web page:
        %{
            web(['text://' fullHTML]);
        %}
        % Save as file:
        %{
           fid = fopen('uifig_raw.html','w');
           fprintf(fid,'%s',fullHTML);
           fclose(fid);
        %}        
        end % getHTML    

    end % Public Static Methods
        
    methods (Static = true, Access = private)
        function [win] = getWebWindow(uifigurewindow)
            mlapptools.toggleWarnings('off')
            % Test if uifigurewindow is a valid handle
            if ~isa(uifigurewindow,'matlab.ui.Figure') || ...
                isempty(struct(uifigurewindow).ControllerInfo)
                msgID = 'mlapptools:getWebWindow:NotUIFigure';
                error(msgID, 'The provided window handle is not of a UIFigure.');
            end
            
            tic
            while true && (toc < mlapptools.QUERY_TIMEOUT)
                try
                    hController = struct(struct(uifigurewindow).Controller);
                    % Check for Controller version:
                    switch subsref(ver('matlab'), substruct('.','Version'))
                      case {'9.0','9.1'} % R2016a or R2016b
                        win = hController.Container.CEF;
                      otherwise  % R2017a onward
                        win = struct(hController.PlatformHost).CEF;
                    end
                    break
                catch err
                    if strcmp(err.identifier, 'MATLAB:nonExistentField')
                        pause(0.01)
                    else
                        mlapptools.toggleWarnings('on')
                        rethrow(err)
                    end
                end
            end
            mlapptools.toggleWarnings('on')
            
            if toc >= mlapptools.QUERY_TIMEOUT
                msgID = 'mlapptools:getWidgetID:QueryTimeout';
                error(msgID, ...
                    'WidgetID query timed out after %u seconds, UI needs more time to load', ...
                    mlapptools.QUERY_TIMEOUT);
            end
        end % getWebWindow
            
        
        function [data_tag] = getDataTag(uielement)
            mlapptools.toggleWarnings('off')
            data_tag = char(struct(uielement).Controller.ProxyView.PeerNode.getId);
            mlapptools.toggleWarnings('on')
        end % getDataTag
        
        
        function [widgetID] = getWidgetID(win, data_tag)
            widgetquerystr = sprintf('dojo.getAttr(dojo.query("[data-tag^=''%s''] > div")[0], "widgetid")', data_tag);
            
            tic
            while true && (toc < mlapptools.QUERY_TIMEOUT)
                try
                    widgetID = win.executeJS(widgetquerystr);
                    widgetID = widgetID(2:end-1);
                    break
                catch err
                    if ~isempty(strfind(err.message, 'JavaScript error: Uncaught ReferenceError: dojo is not defined')) || ...
                            ~isempty(strfind(err.message, 'Cannot read property ''widgetid'' of null'))
                        pause(0.01)
                    else
                        mlapptools.toggleWarnings('on')
                        rethrow(err)
                    end
                end
            end
            mlapptools.toggleWarnings('on')
            
            if toc >= mlapptools.QUERY_TIMEOUT
                msgID = 'mlapptools:getWidgetID:QueryTimeout';
                error(msgID, ...
                      'widgetID query timed out after %u seconds, UI needs more time to load', ...
                      mlapptools.QUERY_TIMEOUT);
            end
        end % getWidgetID
        
        
        function [win, widgetID] = getWebElements(uielement)
            % Get a handle to the webwindow
            win = mlapptools.getWebWindow(uielement.Parent);
            
            % Find which element of the DOM we want to edit
            data_tag = mlapptools.getDataTag(uielement);
            
            % Manipulate the DOM via a JS command
            widgetID = mlapptools.getWidgetID(win, data_tag);
        end % getWebElements
        
        
        function toggleWarnings(togglestr)
            switch lower(togglestr)
                case 'on'
                    warning on MATLAB:HandleGraphics:ObsoletedProperty:JavaFrame
                    warning on MATLAB:structOnObject
                case 'off'
                    warning off MATLAB:HandleGraphics:ObsoletedProperty:JavaFrame
                    warning off MATLAB:structOnObject
                otherwise
                    % Do nothing
            end
        end % toggleWarnings
        
       
        function validateAlignmentStr(alignment)
            if ~ischar(alignment)
                msgID = 'mlapptools:alignstring:InvalidInputIype';
                error(msgID, 'Expected ''%s'', inputs of type ''%s'' not supported', ...
                      class('Dev-il'), class(alignment));
            end
            
            validstr = {'left', 'right', 'center', 'justify', 'initial'};
            if ~any(ismember(validstr, alignment))
                msgID = 'mlapptools:alignstring:InvalidAlignmentString';
                error(msgID, 'Invalid string alignment specified: ''%s''', alignment);
            end
        end % validateAlignmentStr
        
        
        function [weight] = validateFontWeight(weight)
            if ischar(weight)
                weight = lower(weight);
                validstrs = {'normal', 'bold', 'bolder', 'lighter', 'initial'};
                
                if ~any(ismember(weight, validstrs))
                    msgID = 'mlapptools:fontWeight:InvalidFontWeightString';
                    error(msgID, 'Invalid font weight specified: ''%s''', weight);
                end
            elseif isnumeric(weight)
                weight = round(weight, -2);
                if weight < 100
                    weight = 100;
                elseif weight > 900
                    weight = 900;
                end
                
                weight = num2str(weight);
            else
                msgID = 'mlapptools:fontWeight:InvalidFontWeight';
                error(msgID, 'Invalid font weight specified: ''%s''', weight);
            end
        end % validateFontWeight
        
        
        function [newcolor] = validateCSScolor(newcolor)
          % TODO
        end % validateCSScolor
        
        
        function ME = checkJavascriptSyntaxError(ME,styleSetStr)        
            if (strcmp(ME.identifier,'cefclient:webwindow:jserror'))                    
                c = strfind(ME.message,'Uncaught SyntaxError:');
                if ~isempty(c)
                  v = str2double(regexp(ME.message(c:end),'-?\d+\.?\d*|-?\d*\.?\d+','match'));
                  msg = ['Syntax error: unexpected token in styleValue: ' styleSetStr(v(1),v(2))];
                  causeException = MException('mlapptools:setStyle:invalidInputs',msg);
                  ME = addCause(ME,causeException);
                end
            end
        end
    end
end
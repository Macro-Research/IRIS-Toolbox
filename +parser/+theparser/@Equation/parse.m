function varargout = parse(this, aux, code, qty, eqn, euc, ~, opt)
% parse  Parse equations and add them to parser.theparser.Equation object
%
% Backend [IrisToolbox] method
% No help provided

% Invoke unit tests
%(
if nargin==2 && isequal(aux, '--test')
    varargout{1} = unitTests( );
    return
end
%)


% 'Label' x=0.8*x{-1}+ex !! x=0;
LABEL_PATTERN =       '\s*(?<LABEL>"[^\n"]*"|''[^\n'']*'')?';
EQUATION_PATTERN =    '(?<EQUATION>[^;]+);';

%--------------------------------------------------------------------------

%
% Split the code block into individual equations
%
listEquations = this.splitCodeIntoEquations(code);
if isempty(listEquations)
    varargout = { qty, eqn };
    return
end

%
% Separate labels and equations
%
ptn = [LABEL_PATTERN, EQUATION_PATTERN];
tkn = regexp(listEquations, ptn, 'names', 'once');
tkn( cellfun(@isempty, tkn) ) = [ ];
tkn = [ tkn{:} ];

listLabels = { tkn.LABEL };
listEquations = { tkn.EQUATION };
listEquations = regexprep(listEquations, '\s+', '');
numEquations = numel(listEquations);

%
% Option EquationSwitch= overrides in-file commands !!: and :!!
%
if ~isequal(opt.EquationSwitch, @auto)
    listEquations = strrep( ...
        listEquations, ...
        parser.theparser.Equation.READ_STEADY_ONLY, ...
        parser.theparser.Equation.SEPARATE ...
    );
    listEquations = strrep( ...
        listEquations, ...
        parser.theparser.Equation.READ_DYNAMIC_ONLY, ...
        parser.theparser.Equation.SEPARATE ...
    );
end

% Separate dynamic and steady equations
listEquations = readSteadyOnly(listEquations);
listEquations = readDynamicOnly(listEquations);
[listDynamic, listSteady] = parser.theparser.Equation.extractDynamicAndSteady(listEquations);

% Remove equations that are completely empty, no warning
hereRemoveEmptyEquations( );

% Throw a warning for equations that consist of labels only
inxEmptyWarn = cellfun(@isempty, listDynamic) ...
    & cellfun(@isempty, listSteady);
if any(inxEmptyWarn)
    throw( exception.ParseTime('TheParser:EMPTY_EQUATION', 'warning'), ...
        listEquations{inxEmptyWarn} );
    listEquations(inxEmptyWarn) = [ ] ; %#ok<UNRCH>
    listLabels(inxEmptyWarn) = [ ];
    listDynamic(inxEmptyWarn) = [ ];
    listSteady(inxEmptyWarn) = [ ];                
end
if isempty(listEquations)
    varargout = { qty, eqn };
    return
end

% Use steady equations for dynamic equations if requested by user
if this.ApplyEquationSwitch && ~isequal(opt.EquationSwitch, @auto)
    hereApplyEquationSwitch( );
end

% Remove quotation marks from labels
for i = 1 : numel(listLabels)
    % Make sure empty labels are '' and not [1x0 char]
    if numel(listLabels{i})>2
        listLabels{i} = listLabels{i}(2:end-1);
    end
end

% Validate and evaluate time subscripts, and get max and min shifts (these
% only need to be determined from dynamic equations).
[listDynamic, maxShDynamic, minShDynamic] = ...
    parser.theparser.Equation.evalTimeSubs(listDynamic);
[listSteady, maxShSteady, minShSteady] = ...
    parser.theparser.Equation.evalTimeSubs(listSteady);

% Split equations into LHS, sign, and RHS.
[lhsDynamic, signDynamic, rhsDynamic, ixMissingDynamic] = this.splitLhsSignRhs(listDynamic);
[lhsSteady, signSteady, rhsSteady, ixMissingSteady] = this.splitLhsSignRhs(listSteady);

if any(ixMissingDynamic)
    throw( exception.Base('TheParser:EmptyLhsOrRhs', 'error'), ...
        listEquations{ixMissingDynamic} );
end
if any(ixMissingSteady)
    throw( exception.Base('TheParser:EmptyLhsOrRhs', 'error'), ...
        listEquations{ixMissingSteady} );
end

% Split labels into labels and aliases.
[listLabels, alias] = this.splitLabelAlias(listLabels);

if isempty(eqn)
    varargout = { qty, eqn };
    return
end

numEquations = numel(listEquations);
eqn.Input(end+(1:numEquations)) = listEquations;
eqn.Label(end+(1:numEquations)) = listLabels;
eqn.Alias(end+(1:numEquations)) = alias;
eqn.Type(end+(1:numEquations)) = repmat(this.Type, 1, numEquations);
eqn.Dynamic(end+(1:numEquations)) = repmat({char.empty(1, 0)}, 1, numEquations);
eqn.Steady(end+(1:numEquations)) = repmat({char.empty(1, 0)}, 1, numEquations);
eqn.IxHash(end+(1:numEquations)) = false(1, numEquations);

if ~isequal(euc, [ ])
    euc.LhsDynamic(end+(1:numEquations)) = lhsDynamic;
    euc.SignDynamic(end+(1:numEquations)) = signDynamic;
    euc.RhsDynamic(end+(1:numEquations)) = rhsDynamic;
    euc.LhsSteady(end+(1:numEquations)) = lhsSteady;
    euc.SignSteady(end+(1:numEquations)) = signSteady;
    euc.RhsSteady(end+(1:numEquations)) = rhsSteady;
    euc.MaxShDynamic(end+(1:numEquations)) = maxShDynamic;
    euc.MinShDynamic(end+(1:numEquations)) = minShDynamic;
    euc.MaxShSteady(end+(1:numEquations)) = maxShSteady;
    euc.MinShSteady(end+(1:numEquations)) = minShSteady;
end


%<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
varargout = { qty, eqn };
%<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

return

    function hereApplyEquationSwitch( )
        inxEmptyDynamic = cellfun('isempty', listDynamic);
        inxEmptySteady = cellfun('isempty', listSteady);
        inxToApply = ~inxEmptyDynamic & ~inxEmptySteady;
        if strcmpi(opt.EquationSwitch, 'Dynamic')
            listEquations(inxToApply) = listDynamic(inxToApply);
            listSteady(inxToApply) = { char.empty(1, 0) };
        elseif strcmpi(opt.EquationSwitch, 'Steady')
            listDynamic(inxToApply) = listSteady(inxToApply);
            listEquations(inxToApply) = listSteady(inxToApply);
            listSteady(inxToApply) = { char.empty(1, 0) };
        end
    end%


    function hereRemoveEmptyEquations( )
        inxEmptyCanBeRemoved = ...
            cellfun(@isempty, listLabels) ...
            & cellfun(@isempty, listDynamic) ...
            & cellfun(@isempty, listSteady);
        if any(inxEmptyCanBeRemoved)
            listEquations(inxEmptyCanBeRemoved) = [ ];
            listLabels(inxEmptyCanBeRemoved) = [ ];
            listDynamic(inxEmptyCanBeRemoved) = [ ];
            listSteady(inxEmptyCanBeRemoved) = [ ];
        end
    end%

end%


%
% Local Functions
%






function input = readSteadyOnly(input)
    separator = parser.theparser.Equation.READ_STEADY_ONLY;
    lenSeparator = length(separator);
    posSeparator = strfind(input, separator);
    inxFound = ~cellfun(@isempty, posSeparator);
    if ~any(inxFound)
        return
    end
    input(inxFound) = cellfun( @(eqn, pos) eqn(pos+lenSeparator:end), ...
                                 input(inxFound), ...
                                 posSeparator(inxFound), ...
                                 'UniformOutput', false );
end%




function input = readDynamicOnly(input)
    separator = parser.theparser.Equation.READ_DYNAMIC_ONLY;
    lenSeparator = length(separator);
    posSeparator = strfind(input, separator);
    inxFound = ~cellfun(@isempty, posSeparator);
    if ~any(inxFound)
        return
    end
    input(inxFound) = cellfun( @(eqn, pos) eqn(1:pos-1), ...
                                 input(inxFound), ...
                                 posSeparator(inxFound), ...
                                 'UniformOutput', false );
end%




% 
% Unit Tests
%(
function tests = unitTests( )
    tests = functiontests({
        @setupOnce
        @equationSwitchAutoTest
        @equationSwitchDynamicTest
        @equationSwitchSteadyTest
    });
    tests = reshape(tests, [ ], 1);
end%


function setupOnce(testCase)
    obj = parser.theparser.Equation( );
    obj.Type = 2;
    code = [
        "a = a{-1} :!! a = 0;"
        "b = b{-1} !!: b = 0;"
        "c = c{-1} !! c = 0;"
        "d = d{-1};"
    ];
    code = char(join(code, " "));
    testCase.TestData.Obj = obj;
    testCase.TestData.Code = code;
end%


function equationSwitchAutoTest(testCase)
    obj = testCase.TestData.Obj;
    code = testCase.TestData.Code;
    eqn = model.component.Equation( );
    eun = parser.EquationUnderConstruction( );
    opt = struct( );
    opt.EquationSwitch = @auto;
    [~, eqn] = parse(obj, [ ], code, [ ], eqn, eun, [ ], opt);
    exp_Input = {'a=a{-1}', 'b=0', 'c=c{-1}!!c=0', 'd=d{-1}'};
    assertEqual(testCase, eqn.Input, exp_Input);
    assertEqual(testCase, cellfun('isempty', eun.LhsSteady), [true, true, false, true]);
end%


function equationSwitchDynamicTest(testCase);
    obj = testCase.TestData.Obj;
    code = testCase.TestData.Code;
    eqn = model.component.Equation( );
    eun = parser.EquationUnderConstruction( );
    opt.EquationSwitch = 'Dynamic';
    [~, eqn] = parse(obj, [ ], code, [ ], eqn, eun, [ ], opt);
    exp_Input = {'a=a{-1}', 'b=b{-1}', 'c=c{-1}', 'd=d{-1}'};
    assertEqual(testCase, eqn.Input, exp_Input);
    assertEqual(testCase, cellfun('isempty', eun.LhsSteady), true(1, 4));
end%


function equationSwitchSteadyTest(testCase);
    obj = testCase.TestData.Obj;
    code = testCase.TestData.Code;
    eqn = model.component.Equation( );
    eun = parser.EquationUnderConstruction( );
    opt.EquationSwitch = 'Steady';
    [~, eqn] = parse(obj, [ ], code, [ ], eqn, eun, [ ], opt);
    exp_Input = {'a=0', 'b=0', 'c=0', 'd=d{-1}'};
    assertEqual(testCase, eqn.Input, exp_Input);
    assertEqual(testCase, cellfun('isempty', eun.LhsSteady), true(1, 4));
end%
%)

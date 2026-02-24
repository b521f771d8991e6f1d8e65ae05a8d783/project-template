export function ConditionallyApplyProp({
	children,
	onCondition,
	container: Container,
	containerProps = {},
}: React.PropsWithChildren<{
	onCondition: boolean;
	container: React.ElementType;
	containerProps?: any;
}>) {
	return onCondition ? (
		<Container {...containerProps}>{children}</Container>
	) : (
		<>{children}</>
	);
}
